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

      Keyword.get(var, -1)  →  List.last(var)
      Keyword.get(var, 0)   →  List.first(var)
      Keyword.get(var, n)   →  Enum.at(var, n)

  Only fixes when the list argument is a simple variable name.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # ── Check ──────────────────────────────────────────────────────

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node) do
          {:ok, meta} -> {node, [build_issue(meta) | acc]}
          :skip -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  # Direct call: Keyword.get(list, integer_key)
  defp detect({{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [_list, key]}) do
    if integer_literal?(key), do: {:ok, meta}, else: :skip
  end

  # Piped call: expr |> Keyword.get(integer_key)
  defp detect({{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [key]}) do
    if integer_literal?(key), do: {:ok, meta}, else: :skip
  end

  defp detect(_), do: :skip

  # In the AST, positive integers are bare values (is_integer/1).
  # Negative integers are {:-, _, [positive_integer]} (unary minus).
  defp integer_literal?(n) when is_integer(n), do: true
  defp integer_literal?({:-, _, [n]}) when is_integer(n), do: true
  defp integer_literal?(_), do: false

  # ── Fix ────────────────────────────────────────────────────────

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_fix(node) do
          {:ok, patch} -> {node, [patch | acc]}
          :skip -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # Direct: Keyword.get(list, integer) — only when list is a simple var
  # (matches the legacy regex's `(\w+)` capture group).
  defp detect_fix(
         {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, _meta, [list, key]} = node
       ) do
    with {:ok, n} <- integer_value(key),
         {:ok, var} <- simple_var(list) do
      {:ok, %{range: Sourceror.get_range(node), change: direct_replacement(var, n)}}
    else
      _ -> :skip
    end
  end

  # Piped: expr |> Keyword.get(integer)
  defp detect_fix({{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, _meta, [key]} = node) do
    case integer_value(key) do
      {:ok, n} ->
        {:ok, %{range: Sourceror.get_range(node), change: piped_replacement(n)}}

      :error ->
        :skip
    end
  end

  defp detect_fix(_), do: :skip

  defp integer_value(n) when is_integer(n), do: {:ok, n}
  defp integer_value({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp integer_value({:-, _, [n]}) when is_integer(n), do: {:ok, -n}
  defp integer_value({:-, _, [{:__block__, _, [n]}]}) when is_integer(n), do: {:ok, -n}
  defp integer_value(_), do: :error

  defp simple_var({name, _, ctx}) when is_atom(name) and is_atom(ctx),
    do: {:ok, Atom.to_string(name)}

  defp simple_var(_), do: :error

  # ── Replacements ───────────────────────────────────────────────

  defp direct_replacement(var, -1), do: "List.last(#{var})"
  defp direct_replacement(var, 0), do: "List.first(#{var})"
  defp direct_replacement(var, n), do: "Enum.at(#{var}, #{n})"

  defp piped_replacement(-1), do: "List.last()"
  defp piped_replacement(0), do: "List.first()"
  defp piped_replacement(n), do: "Enum.at(#{n})"

  # ── Issue ──────────────────────────────────────────────────────

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
