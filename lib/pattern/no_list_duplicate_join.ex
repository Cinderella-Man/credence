defmodule Credence.Pattern.NoListDuplicateJoin do
  @moduledoc """
  Detects `List.duplicate(string, n) |> Enum.join()` (or `Enum.concat` with join)
  and suggests `String.duplicate/2` instead.

  When the goal is to repeat a string N times, `String.duplicate/2` is the
  idiomatic function. LLMs often produce `List.duplicate/2` followed by
  `Enum.join/1` to achieve the same result, which is less readable and
  allocates an intermediate list.

  ## Bad

      List.duplicate(pattern, n) |> Enum.join()
      Enum.join(List.duplicate(pattern, n))

  ## Good

      String.duplicate(pattern, n)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Piped: list |> List.duplicate(n) |> Enum.join()
        {:|>, _,
         [
           {:|>, _, [_list, {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, dup_meta, _}]},
           {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, []}
         ]} = node,
        acc ->
          {node, [build_issue(dup_meta) | acc]}

        # Nested: Enum.join(List.duplicate(list, n))
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _,
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

  # Piped: list |> List.duplicate(n) |> Enum.join()
  defp rewrite(
         {:|>, _,
          [
            {:|>, _, [list, {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, _, [n]}]},
            {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, []}
          ]}
       ) do
    string_duplicate_ast(list, n)
  end

  # Nested: Enum.join(List.duplicate(list, n))
  defp rewrite(
         {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _,
          [
            {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, _, [list, n]}
          ]}
       ) do
    string_duplicate_ast(list, n)
  end

  defp rewrite(node), do: node

  defp string_duplicate_ast(string, n) do
    {{:., [], [{:__aliases__, [], [:String]}, :duplicate]}, [], [string, n]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_list_duplicate_join,
      message:
        "`List.duplicate/2` piped into `Enum.join/1` " <>
          "is a roundabout way to repeat a string.\n\n" <>
          "Simplify:\n\n" <>
          "    String.duplicate(string, n)",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
