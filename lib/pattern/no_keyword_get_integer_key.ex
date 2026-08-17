defmodule Credence.Pattern.NoKeywordGetIntegerKey do
  @moduledoc """
  Detects `Keyword.get(list, integer)` where the key is an integer literal.

  `Keyword.get/2` requires atom keys — its guard is `when is_atom(key)`.
  Passing an integer key always crashes at runtime with `FunctionClauseError`.

  LLMs produce this when translating Python's `list[-1]` (last element)
  or `dict[index]` into Elixir, reaching for `Keyword.get` as the
  closest-looking dictionary lookup.

  ## Bad

      Keyword.get(acc, -1)
      Keyword.get(list, 0)
      acc |> Keyword.get(-1)

  ## Good

      List.last(acc)
      List.first(list)
      acc |> List.last()

  ## What is flagged

  Any call to `Keyword.get` with exactly two arguments where the second
  is an integer literal (direct call), or one argument that is an integer
  literal (piped call). Three-argument calls are not flagged.

  ## Auto-fix

  Rewrites based on the index value:

      Keyword.get(list, -1)  →  List.last(list)
      Keyword.get(list, 0)   →  List.first(list)
      Keyword.get(list, n)   →  Enum.at(list, n)

  ## The list argument may be any expression

  It was once "only a simple variable name", and the reason was not a safety
  property — the comment beside it said "matches the legacy regex's `(\w+)`
  capture group". A regex could only name a bare identifier; this rule works on
  the AST and has no such limit. Meanwhile `check/2` never had the restriction, so
  four shapes were reported and left unfixed:

      Keyword.get(@acc, -1)            module attribute
      Keyword.get(state.items, -1)     dotted access
      Keyword.get(build_list(), 0)     function call
      Keyword.get([a: 1], -1)          literal list

  Widening is sound for any expression, because `Keyword.get/2` is guarded
  `when is_atom(key)` — an integer key raises `FunctionClauseError` on **every**
  input, whatever the first argument is. There is no working behaviour to
  preserve, and the argument is evaluated exactly once before and after, so a
  side-effecting expression is not run twice.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    piped = piped_get_positions(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node, piped) do
          {:ok, meta} -> {node, [build_issue(meta) | acc]}
          :skip -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  # Direct call: Keyword.get(list, integer_key). Only when NOT piped — a 2-arg
  # node that is the RHS of a pipe is really `Keyword.get/3` (piped list + key +
  # default), so its second arg is the DEFAULT, not the key (the rule does not
  # flag 3-arg calls).
  defp detect({{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [list, key]}, piped) do
    if not MapSet.member?(piped, position(meta)) and not atom_literal?(list) and
         integer_literal?(key),
       do: {:ok, meta},
       else: :skip
  end

  # Piped call: expr |> Keyword.get(integer_key). A 1-arg node only ever occurs
  # in a pipe (Keyword.get needs ≥2 args), so the sole arg is the key.
  defp detect({{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [key]}, _piped) do
    if integer_literal?(key), do: {:ok, meta}, else: :skip
  end

  defp detect(_, _), do: :skip

  # Positions of `Keyword.get` calls that are the RHS of a `|>` (their list
  # argument comes from the pipe, shifting the explicit args left by one).
  defp piped_get_positions(ast) do
    {_ast, set} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, _}]} = node, acc ->
          {node, MapSet.put(acc, position(meta))}

        node, acc ->
          {node, acc}
      end)

    set
  end

  defp position(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

  # Positives are `{:__block__, _, [n]}` (Sourceror wraps int literals).
  # Negatives are `{:-, _, [{:__block__, _, [n]}]}` — unary minus over
  # a wrapped positive.
  defp integer_literal?({:__block__, _, [n]}) when is_integer(n), do: true
  defp integer_literal?({:-, _, [{:__block__, _, [n]}]}) when is_integer(n), do: true
  defp integer_literal?(_), do: false

  @impl true
  def fix_patches(ast, _opts) do
    piped = piped_get_positions(ast)

    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_fix(node, piped) do
          {:ok, patch} -> {node, [patch | acc]}
          :skip -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # Direct: Keyword.get(list, integer) — only when list is a simple var
  # (matches the legacy regex's `(\w+)` capture group) and the call is NOT piped
  # (a piped 2-arg node is `Keyword.get/3`, whose second arg is the default).
  defp detect_fix(
         {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [list, key]} = node,
         piped
       ) do
    with false <- MapSet.member?(piped, position(meta)),
         false <- atom_literal?(list),
         {:ok, n} <- integer_value(key) do
      {:ok,
       %{
         range: Sourceror.get_range(node),
         change: direct_replacement(Sourceror.to_string(list), n)
       }}
    else
      _ -> :skip
    end
  end

  # Piped: expr |> Keyword.get(integer)
  defp detect_fix({{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, _meta, [key]} = node, _piped) do
    case integer_value(key) do
      {:ok, n} ->
        {:ok, %{range: Sourceror.get_range(node), change: piped_replacement(n)}}

      :error ->
        :skip
    end
  end

  defp detect_fix(_, _), do: :skip

  # `Keyword.get(:timeout, 5000)` is not an integer-key lookup — it is
  # `NoKeywordGetWithAtomFirstArg`'s defect, arguments swapped, repaired by
  # unwrapping to the second argument. Rewriting it to `Enum.at(:timeout, 5000)`
  # is nonsense, and two rules claiming one defect is dispatch contention.
  #
  # This was masked rather than handled: the fix used to require the first
  # argument to be a bare identifier, which excluded an atom literal by accident,
  # while `check/2` reported it all along. Widening the fix removed the accident
  # and exposed the over-report underneath, so both callbacks now decline it.
  defp atom_literal?({:__block__, _, [atom]}) when is_atom(atom), do: true
  defp atom_literal?(_node), do: false

  defp integer_value({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp integer_value({:-, _, [{:__block__, _, [n]}]}) when is_integer(n), do: {:ok, -n}
  defp integer_value(_), do: :error

  defp direct_replacement(var, -1), do: "List.last(#{var})"
  defp direct_replacement(var, 0), do: "List.first(#{var})"
  defp direct_replacement(var, n), do: "Enum.at(#{var}, #{n})"

  defp piped_replacement(-1), do: "List.last()"
  defp piped_replacement(0), do: "List.first()"
  defp piped_replacement(n), do: "Enum.at(#{n})"

  defp build_issue(meta) do
    %Issue{
      rule: :no_keyword_get_integer_key,
      message: """
      `Keyword.get/2` requires atom keys — integer keys always crash \
      at runtime with `FunctionClauseError`.

      This is usually a Python `list[-1]` translation. Use list \
      access functions instead:

          Keyword.get(list, -1)    →    List.last(list)
          Keyword.get(list, 0)     →    List.first(list)
          Keyword.get(list, n)     →    Enum.at(list, n)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
