defmodule Credence.Pattern.NoListDuplicateFlatten do
  @moduledoc """
  Detects `Enum.concat(List.duplicate(list, n))` (or the piped
  `list |> List.duplicate(n) |> Enum.concat()`) and suggests
  `Enum.flat_map/2` instead.

  LLMs frequently produce this two-step pattern when they need to
  "tile" or "repeat" a list `n` times: first `List.duplicate/2` to
  create a list of copies, then `Enum.concat/1` to merge them.
  `Enum.flat_map/2` does the same work in a single pass.

  ## Why this is narrowed to `Enum.concat` + variable + literal count

  This rule is deliberately restricted to the cases where the rewrite
  gives the *exact same answer* for every input:

    * **`Enum.concat/1` only, never `List.flatten/1`.** `Enum.concat`
      merges one level; `Enum.flat_map` does too, so they agree. But
      `List.flatten/1` flattens *recursively*, so
      `List.flatten(List.duplicate([[1], [2]], 2))` is `[1, 2, 1, 2]`
      while `Enum.flat_map(1..2, fn _ -> [[1], [2]] end)` is
      `[[1], [2], [1], [2]]`. Different answer → not rewritten.

    * **The repetition count must be a positive integer literal.**
      The rewrite uses `1..n`. For `n == 0` the original yields `[]`
      but `1..0` is a *descending* range (`[1, 0]`) so the rewrite runs
      twice; for negative `n`, `List.duplicate/2` raises but `1..n`
      would not. Only a literal `n >= 1` is provably safe, so a runtime
      variable count is left untouched.

    * **The duplicated value must be a bare variable.** `List.duplicate`
      evaluates its argument once; the `fn _ -> value end` closure
      evaluates it `n` times. For an arbitrary expression that changes
      side effects, so only a side-effect-free variable reference is
      rewritten.

  ## Bad

      list
      |> List.duplicate(3)
      |> Enum.concat()

      Enum.concat(List.duplicate(list, 3))

  ## Good

      Enum.flat_map(1..3, fn _ -> list end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case match_dup_concat(node) do
          {list, n, dup_meta} ->
            if fixable?(list, n) do
              {node, [build_issue(dup_meta) | acc]}
            else
              {node, acc}
            end

          nil ->
            {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &rewrite/1)
  end

  defp rewrite(node) do
    case match_dup_concat(node) do
      {list, n, _dup_meta} ->
        if fixable?(list, n), do: flat_map_ast(list, n), else: node

      nil ->
        node
    end
  end

  # Piped: list |> List.duplicate(n) |> Enum.concat()
  defp match_dup_concat(
         {:|>, _,
          [
            {:|>, _, [list, {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, dup_meta, [n]}]},
            {{:., _, [{:__aliases__, _, [:Enum]}, :concat]}, _, []}
          ]}
       ),
       do: {list, n, dup_meta}

  # Nested: Enum.concat(List.duplicate(list, n))
  defp match_dup_concat(
         {{:., _, [{:__aliases__, _, [:Enum]}, :concat]}, _,
          [
            {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, dup_meta, [list, n]}
          ]}
       ),
       do: {list, n, dup_meta}

  defp match_dup_concat(_), do: nil

  # Only rewrite when the answer provably cannot change:
  #   * the duplicated value is a bare variable (no re-evaluation hazard), and
  #   * the count is a positive integer literal (so `1..n` is a non-empty
  #     ascending range and never raises).
  defp fixable?(list, n), do: variable?(list) and positive_int_literal?(n)

  defp variable?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp variable?(_), do: false

  defp positive_int_literal?({:__block__, _, [int]}) when is_integer(int) and int >= 1, do: true
  defp positive_int_literal?(int) when is_integer(int) and int >= 1, do: true
  defp positive_int_literal?(_), do: false

  defp flat_map_ast(list, n) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :flat_map]}, [],
     [
       {:.., [], [1, n]},
       {:fn, [], [{:->, [], [[{:_, [], Elixir}], list]}]}
     ]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_list_duplicate_flatten,
      message:
        "`List.duplicate/2` piped into `Enum.concat/1` does two passes " <>
          "when `Enum.flat_map/2` does the same in one.\n\n" <>
          "Simplify:\n\n" <>
          "    Enum.flat_map(1..n, fn _ -> list end)",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
