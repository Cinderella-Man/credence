defmodule Credence.Rule.NoManualStringReverse do
  @moduledoc """
  Readability & performance rule: Detects the pattern
  `String.graphemes(s) |> Enum.reverse() |> Enum.join()` which is a manual
  reimplementation of `String.reverse/1`.

  `String.reverse/1` handles Unicode grapheme clusters correctly and avoids
  creating an intermediate list, making it both clearer and faster.

  ## Bad

      reversed = str |> String.graphemes() |> Enum.reverse() |> Enum.join()

  ## Good

      reversed = String.reverse(str)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match a pipeline: String.graphemes(...) |> Enum.reverse() |> Enum.join()
        # In the AST, a pipeline `a |> b |> c` is nested as `c(b(a))` via |>,
        # i.e. {:|>, _, [inner_pipe, outer_call]}
        #
        # Outermost: |> Enum.join()
        {:|>, meta,
         [
           # Middle: |> Enum.reverse()
           {:|>, _,
            [
              # Inner: String.graphemes(...)
              {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _},
              {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, _}
            ]},
           {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, _}
         ]} = node,
        issues ->
          issue = %Issue{
            rule: :no_manual_string_reverse,
            severity: :warning,
            message:
              "Use `String.reverse/1` instead of `String.graphemes/1 |> Enum.reverse/0 |> Enum.join/0`. It is clearer and avoids creating an intermediate list.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        # Also match the nested-call form (no pipe operator):
        # Enum.join(Enum.reverse(String.graphemes(s)))
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
            [
              {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}
            ]}
         ]} = node,
        issues ->
          issue = %Issue{
            rule: :no_manual_string_reverse,
            severity: :warning,
            message:
              "Use `String.reverse/1` instead of `String.graphemes/1 |> Enum.reverse/0 |> Enum.join/0`. It is clearer and avoids creating an intermediate list.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end
end
