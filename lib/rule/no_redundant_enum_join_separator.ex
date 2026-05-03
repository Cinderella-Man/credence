defmodule Credence.Rule.NoRedundantEnumJoinSeparator do
  @moduledoc """
  Readability rule: Detects `Enum.join("")` and `Enum.map_join("", mapper)`
  where the empty-string separator is passed explicitly.

  `Enum.join/1` and `Enum.map_join/2` already default to `""`, so the argument
  adds visual noise without changing behaviour.

  ## Bad

      graphemes |> Enum.join("")
      Enum.join(list, "")
      items |> Enum.map_join("", &to_string/1)
      Enum.map_join(items, "", &to_string/1)

  ## Good

      graphemes |> Enum.join()
      Enum.join(list)
      items |> Enum.map_join(&to_string/1)
      Enum.map_join(items, &to_string/1)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct call: Enum.join(list, "")
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, meta, [_list, ""]} = node, issues ->
          {node, [build_issue(meta) | issues]}

        # In a pipe the separator is the only explicit arg: ... |> Enum.join("")
        # The piped value becomes the first arg, so the AST call has [""]
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, meta, [""]} = node, issues ->
          {node, [build_issue(meta) | issues]}

        # Direct call: Enum.map_join(list, "", mapper)
        {{:., _, [{:__aliases__, _, [:Enum]}, :map_join]}, meta, [_list, "", _mapper]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        # In a pipe the separator is the first explicit arg: ... |> Enum.map_join("", mapper)
        # The piped value becomes the first arg, so the AST call has ["", mapper]
        {{:., _, [{:__aliases__, _, [:Enum]}, :map_join]}, meta, ["", _mapper]} = node, issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_enum_join_separator,
      message:
        "`Enum.join/1` and `Enum.map_join/2` already default to an empty string separator. " <>
          "Remove the redundant `\"\"` argument.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
