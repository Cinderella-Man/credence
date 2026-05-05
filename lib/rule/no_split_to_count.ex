defmodule Credence.Rule.NoSplitToCount do
  @moduledoc """
  Detects `length(String.split(string, separator)) - 1` used to count
  substring occurrences.

  This is a direct translation of Python's `str.count(target)`. While it
  works correctly, it allocates the full list of split segments only to
  count them and throw the list away.

  ## Bad

      count = length(String.split(downcased, target)) - 1

  ## Good

      # For single-character targets, count matching graphemes directly:
      count = downcased |> String.graphemes() |> Enum.count(&(&1 == target))

      # For multi-character targets, use the Erlang binary matching BIF:
      count = :binary.matches(downcased, target) |> length()

  ## Auto-fix

  Not auto-fixable — the best replacement depends on whether the
  separator is a single character or a multi-character substring.
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # length(String.split(str, sep)) - 1
        {:-, meta,
         [
           {:length, _,
            [{{:., _, [{:__aliases__, _, [:String]}, :split]}, _, [_str, _sep]}]},
           1
         ]} = node,
        acc ->
          {node, [build_issue(meta) | acc]}

        # length(String.split(str, sep)) - 1 (with unary minus AST for 1)
        {:-, meta,
         [
           {:length, _,
            [{{:., _, [{:__aliases__, _, [:String]}, :split]}, _, [_str, _sep]}]},
           {:__block__, _, [1]}
         ]} = node,
        acc ->
          {node, [build_issue(meta) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_split_to_count,
      message: """
      `length(String.split(str, sep)) - 1` allocates a list of all split \
      segments just to count them.

      For single-character targets, count graphemes directly:

          str |> String.graphemes() |> Enum.count(&(&1 == target))

      For multi-character targets, use the Erlang BIF:

          :binary.matches(str, target) |> length()
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
