defmodule Credence.Pattern.NoListDuplicateFlatten do
  @moduledoc """
  Detects `List.duplicate(list, n) |> List.flatten()` (or `Enum.concat`)
  and suggests `Enum.flat_map/2` instead.

  LLMs frequently produce this two-step pattern when they need to
  "tile" or "repeat" a list: first `List.duplicate/2` to create a
  list of copies, then `List.flatten/1` or `Enum.concat/1` to merge them.
  `Enum.flat_map/2` does the same work in a single pass and is the idiomatic
  Elixir idiom for flat-mapping over a range.

  ## Bad

      chars
      |> List.duplicate(repetitions)
      |> List.flatten()

      List.flatten(List.duplicate(list, 3))

      chars
      |> List.duplicate(repetitions)
      |> Enum.concat()

      Enum.concat(List.duplicate(list, 3))

  ## Good

      Enum.flat_map(1..repetitions, fn _ -> chars end)

      Enum.flat_map(1..3, fn _ -> list end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Piped: list |> List.duplicate(n) |> List.flatten()
        {:|>, _,
         [
           {:|>, _, [_list, {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, dup_meta, _}]},
           {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, _, []}
         ]} = node,
        acc ->
          {node, [build_issue(dup_meta) | acc]}

        # Nested: List.flatten(List.duplicate(list, n))
        {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, _,
         [
           {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, dup_meta, _}
         ]} = node,
        acc ->
          {node, [build_issue(dup_meta) | acc]}

        # Piped: list |> List.duplicate(n) |> Enum.concat()
        {:|>, _,
         [
           {:|>, _, [_list, {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, dup_meta, _}]},
           {{:., _, [{:__aliases__, _, [:Enum]}, :concat]}, _, []}
         ]} = node,
        acc ->
          {node, [build_issue(dup_meta) | acc]}

        # Nested: Enum.concat(List.duplicate(list, n))
        {{:., _, [{:__aliases__, _, [:Enum]}, :concat]}, _,
         [
           {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, dup_meta, _}
         ]} = node,
        acc ->
          {node, [build_issue(dup_meta) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &rewrite/1)
  end

  # Piped: list |> List.duplicate(n) |> List.flatten()
  defp rewrite(
         {:|>, _,
          [
            {:|>, _, [list, {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, _, [n]}]},
            {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, _, []}
          ]}
       ) do
    flat_map_ast(list, n)
  end

  # Nested: List.flatten(List.duplicate(list, n))
  defp rewrite(
         {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, _,
          [
            {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, _, [list, n]}
          ]}
       ) do
    flat_map_ast(list, n)
  end

  # Piped: list |> List.duplicate(n) |> Enum.concat()
  defp rewrite(
         {:|>, _,
          [
            {:|>, _, [list, {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, _, [n]}]},
            {{:., _, [{:__aliases__, _, [:Enum]}, :concat]}, _, []}
          ]}
       ) do
    flat_map_ast(list, n)
  end

  # Nested: Enum.concat(List.duplicate(list, n))
  defp rewrite(
         {{:., _, [{:__aliases__, _, [:Enum]}, :concat]}, _,
          [
            {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, _, [list, n]}
          ]}
       ) do
    flat_map_ast(list, n)
  end

  defp rewrite(node), do: node

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
        "`List.duplicate/2` piped into `List.flatten/1` or `Enum.concat/1` " <>
          "does two passes when `Enum.flat_map/2` does the same in one.\n\n" <>
          "Simplify:\n\n" <>
          "    Enum.flat_map(1..n, fn _ -> list end)",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
