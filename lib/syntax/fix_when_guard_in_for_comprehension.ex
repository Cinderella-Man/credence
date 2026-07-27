defmodule Credence.Syntax.FixWhenGuardInForComprehension do
  @moduledoc """
  Fixes `when` keyword misused as a filter in `for` comprehensions.

  LLMs (Python-isms) write `when` guards inside `for` comprehension
  generator patterns. Elixir's `when` is reserved for guards and is not
  allowed in `for` comprehension filters — the parser errors with
  "syntax error before: when". The intended filter should be a bare
  boolean expression.

  ## Bad (won't parse)

      for {name, price, _qty} <- items, when price > 100 do
        name
      end

  ## Good

      for {name, price, _qty} <- items, price > 100 do
        name
      end
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # `, when ` on the same line as the generator (comma-separated filter)
  @when_filter_same_line ~r/,\s+when\s+/
  # `when ` at the start of a line (after indentation), on a line after the generator
  @when_filter_new_line ~r/^(\s+)when\s+/

  @impl true
  def analyze(source) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if when_filter_in_for_context?(line, line_no, lines) do
        [build_issue(line_no)]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {line, line_no} ->
      if when_filter_in_for_context?(line, line_no, lines) do
        fix_when_line(line)
      else
        line
      end
    end)
  end

  defp when_filter_in_for_context?(line, line_no, lines) do
    not comment?(line) and
      ((Regex.match?(@when_filter_same_line, line) and
          has_for_generator_context?(line, line_no, lines)) or
         (Regex.match?(@when_filter_new_line, line) and
            preceding_has_for_generator?(line_no, lines)))
  end

  defp has_for_generator_context?(line, line_no, lines) do
    String.contains?(line, "<-") or preceding_has_for_generator?(line_no, lines)
  end

  defp preceding_has_for_generator?(line_no, lines) do
    lines
    |> Enum.take(line_no - 1)
    |> Enum.reverse()
    |> Enum.any?(fn prev_line ->
      not comment?(prev_line) and
        String.contains?(prev_line, "<-") and
        String.contains?(prev_line, "for ")
    end)
  end

  defp fix_when_line(line) do
    cond do
      Regex.match?(@when_filter_same_line, line) ->
        Regex.replace(@when_filter_same_line, line, ", ")

      Regex.match?(@when_filter_new_line, line) ->
        Regex.replace(@when_filter_new_line, line, "\\1")

      true ->
        line
    end
  end

  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_when_guard_in_for_comprehension,
      message:
        "`when` cannot be used as a filter in a `for` comprehension. " <>
          "Use a bare boolean expression instead.",
      meta: %{line: line_no}
    }
  end
end
