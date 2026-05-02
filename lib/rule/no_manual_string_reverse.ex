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
        # Pipeline form: ... |> String.graphemes() |> Enum.reverse() |> Enum.join()
        #
        # `a |> b() |> c()` parses as {:|>, _, [{:|>, _, [a, b]}, c]}.
        # So the outer pipe has `c` on the right and the inner chain on the left.
        # We check: right == Enum.join, predecessor == Enum.reverse, predecessor's predecessor == String.graphemes.
        {:|>, meta, [left, right]} = node, issues ->
          if remote_call?(right, :Enum, :join) and remote_call?(rightmost(left), :Enum, :reverse) do
            grandparent =
              case left do
                {:|>, _, [inner_left, _]} -> rightmost(inner_left)
                _ -> nil
              end

            if grandparent != nil and remote_call?(grandparent, :String, :graphemes) do
              {node, [build_issue(meta) | issues]}
            else
              {node, issues}
            end
          else
            {node, issues}
          end

        # Nested call form: Enum.join(Enum.reverse(String.graphemes(s)))
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
            [
              {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}
            ]}
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_string_reverse,
      message:
        "Use `String.reverse/1` instead of `String.graphemes/1 |> Enum.reverse/0 |> Enum.join/0`. " <>
          "It is clearer and avoids creating an intermediate list.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
