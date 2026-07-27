defmodule Credence.Semantic.FixKeywordDoubleColon do
  @moduledoc """
  Fixes the compiler error when `::` (type-annotation operator) is used
  instead of `:` (keyword syntax) in keyword arguments.

  LLMs write `name::expr` in keyword arguments, confusing the `::`
  type-annotation operator with `:` keyword syntax. The compiler emits:

      misplaced operator ::/2

  The fix replaces `::` with `: ` at the diagnostic location.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "misplaced operator ::/2"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_keyword_double_colon,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{position: {line_num, col}}) when is_integer(line_num) and is_integer(col) do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_num - 1) do
      nil ->
        source

      line_str ->
        before_col = String.slice(line_str, 0, col - 1)
        after_col = String.slice(line_str, col + 1, String.length(line_str))
        new_line = before_col <> ": " <> after_col
        new_lines = List.replace_at(lines, line_num - 1, new_line)
        Enum.join(new_lines, "\n")
    end
  end

  def fix(source, _diagnostic), do: source

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
