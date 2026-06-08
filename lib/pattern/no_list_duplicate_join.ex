defmodule Credence.Pattern.NoListDuplicateJoin do
  @moduledoc """
  Detects `List.duplicate(string_literal, n) |> Enum.join()` (and the nested
  `Enum.join(List.duplicate(string_literal, n))`) and suggests
  `String.duplicate/2` instead.

  When the goal is to repeat a string N times, `String.duplicate/2` is the
  idiomatic function. LLMs often produce `List.duplicate/2` followed by
  `Enum.join/1` to achieve the same result, which is less readable and
  allocates an intermediate list.

  ## Safe core: string-literal first argument only

  `Enum.join/1` calls `to_string/1` on each element, so
  `Enum.join(List.duplicate(value, n))` works for **any** `value` — e.g.
  `Enum.join(List.duplicate(7, 3)) == "777"`. `String.duplicate/2`, by contrast,
  requires a binary and raises on anything else (`String.duplicate(7, 3)`
  raises `ArgumentError`). The two are only guaranteed to agree when the
  duplicated value is already a string.

  Since a non-literal first argument (a variable, a function call) cannot be
  proven to be a binary syntactically, this rule fires **only when the
  duplicated value is a string literal**, where the rewrite is exactly
  behaviour-preserving. The `n` argument may be anything: both `List.duplicate/2`
  and `String.duplicate/2` require a non-negative integer and raise identically
  otherwise.

  ## Bad

      List.duplicate("=", n) |> Enum.join()
      Enum.join(List.duplicate("=", n))

  ## Good

      String.duplicate("=", n)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Piped: "literal" |> List.duplicate(n) |> Enum.join()
        {:|>, _,
         [
           {:|>, _,
            [
              {:__block__, _, [s]},
              {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, dup_meta, [_n]}
            ]},
           {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, []}
         ]} = node,
        acc
        when is_binary(s) ->
          {node, [build_issue(dup_meta) | acc]}

        # Nested: Enum.join(List.duplicate("literal", n))
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _,
         [
           {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, dup_meta,
            [{:__block__, _, [s]}, _n]}
         ]} = node,
        acc
        when is_binary(s) ->
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

  # Piped: "literal" |> List.duplicate(n) |> Enum.join()
  defp rewrite(
         {:|>, _,
          [
            {:|>, _,
             [
               {:__block__, _, [s]} = list,
               {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, _, [n]}
             ]},
            {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, []}
          ]}
       )
       when is_binary(s) do
    string_duplicate_ast(list, n)
  end

  # Nested: Enum.join(List.duplicate("literal", n))
  defp rewrite(
         {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _,
          [
            {{:., _, [{:__aliases__, _, [:List]}, :duplicate]}, _,
             [{:__block__, _, [s]} = list, n]}
          ]}
       )
       when is_binary(s) do
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
