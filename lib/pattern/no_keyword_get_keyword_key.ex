defmodule Credence.Pattern.NoKeywordGetKeywordKey do
  @moduledoc """
  Detects `Keyword.get/2` with a keyword-literal second argument and rewrites
  to `Keyword.get/3` with an atom key and default value.

  LLMs repeatedly write `Keyword.get(opts, partial: false)` passing a keyword
  list `[partial: false]` as the second argument instead of the correct
  `Keyword.get(opts, :partial, false)`. The code parses and compiles (a keyword
  list is a valid list argument), but causes `FunctionClauseError` at runtime
  because `Keyword.get/2` guards require an atom key.

  ## Bad

      Keyword.get(opts, partial: false)
      Keyword.get(opts, on_conflict: :replace)

  ## Good

      Keyword.get(opts, :partial, false)
      Keyword.get(opts, :on_conflict, :replace)

  ## What is flagged

  Any call to `Keyword.get` with exactly two arguments where the second is a
  keyword list with exactly one element. Three-argument calls are not flagged
  (their keyword list is a valid default). A piped call with only the keyword
  list is flagged because it is `Keyword.get/2`; a piped call with a key and
  keyword-list default is `Keyword.get/3` and remains valid.

  ## Auto-fix

  Extracts the keyword pair's atom key and value, rewrites to `Keyword.get/3`
  with the atom key and the value as the default:

      Keyword.get(opts, partial: false)  →  Keyword.get(opts, :partial, false)
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

  # Detect: Keyword.get(keywords, kw_list) with exactly 2 args where the second
  # is a keyword list with exactly one element. Only when NOT piped — a 2-arg
  # node that is the RHS of a pipe is really `Keyword.get/3` (piped list + key +
  # default), so its second arg is a valid DEFAULT, not the key.
  defp detect({{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [_list, kw_list]}, piped) do
    if not MapSet.member?(piped, position(meta)) and keyword_literal?(unwrap_block(kw_list)),
      do: {:ok, meta},
      else: :skip
  end

  defp detect({{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [kw_list]}, piped) do
    if MapSet.member?(piped, position(meta)) and keyword_literal?(unwrap_block(kw_list)),
      do: {:ok, meta},
      else: :skip
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

  # A keyword list literal in Sourceror is a plain list of `{key, value}` tuples
  # where the key node carries `format: :keyword` metadata.
  defp keyword_literal?([{key_ast, _value_ast}]) do
    case key_ast do
      {:__block__, meta, _} -> Keyword.get(meta, :format) == :keyword
      _ -> false
    end
  end

  defp keyword_literal?(_), do: false

  # A bracketed list literal (`[partial: false]` vs bare `partial: false`) is
  # wrapped in a `__block__` node by Sourceror — unwrap it so both spellings
  # are treated the same.
  defp unwrap_block({:__block__, _, [list]}) when is_list(list), do: list
  defp unwrap_block(other), do: other

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

  defp detect_fix(
         {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [list, kw_list]} = node,
         piped
       ) do
    with false <- MapSet.member?(piped, position(meta)),
         {:ok, atom_key, default_value} <- extract_keyword_pair(unwrap_block(kw_list)) do
      new_node =
        {{:., [], [{:__aliases__, [], [:Keyword]}, :get]}, [],
         [list, {:__block__, [], [atom_key]}, default_value]}

      {:ok, %{range: Sourceror.get_range(node), change: render(new_node)}}
    else
      _ -> :skip
    end
  end

  defp detect_fix(
         {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [kw_list]} = node,
         piped
       ) do
    with true <- MapSet.member?(piped, position(meta)),
         {:ok, atom_key, default_value} <- extract_keyword_pair(unwrap_block(kw_list)) do
      new_node =
        {{:., [], [{:__aliases__, [], [:Keyword]}, :get]}, [],
         [{:__block__, [], [atom_key]}, default_value]}

      {:ok, %{range: Sourceror.get_range(node), change: render(new_node)}}
    else
      _ -> :skip
    end
  end

  defp detect_fix(_, _), do: :skip

  defp extract_keyword_pair([{key_ast, value_ast}]) do
    case key_ast do
      {:__block__, meta, _} when is_list(meta) ->
        if Keyword.get(meta, :format) == :keyword do
          {:ok, extract_atom(key_ast), value_ast}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp extract_keyword_pair(_), do: :error

  # Sole caller is extract_keyword_pair/1, which only reaches here after matching
  # `{:__block__, meta, _}` — so the input is always a block node, never a bare
  # atom. (A bare-atom clause used to sit below this one; the compiler proved it
  # dead and warned on every build.)
  defp extract_atom({:__block__, _, [atom]}) when is_atom(atom), do: atom

  defp render(node) do
    node
    |> strip_meta()
    |> Sourceror.to_string()
  end

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) ->
        {form, Keyword.drop(meta, [:line, :column, :closing, :last, :end]), args}

      other ->
        other
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_keyword_get_keyword_key,
      message: """
      `Keyword.get/2` requires an atom key — passing a keyword list \
      `[key: value]` as the key always crashes at runtime with \
      `FunctionClauseError`.

      Use the three-argument form instead:

          Keyword.get(opts, partial: false)      →    Keyword.get(opts, :partial, false)
          Keyword.get(opts, on_conflict: :replace) →  Keyword.get(opts, :on_conflict, :replace)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
