defmodule Credence.Syntax.NoEndKeywordVariable do
  @moduledoc """
  Detects and renames `end` used as a variable name.

  LLMs sometimes generate code where `end` is used as a variable name,
  e.g. `end = a + b` followed by a bare `end` return. Since `end` is
  a reserved keyword in Elixir (used to close `do`/`fn`/`if`/etc. blocks),
  this causes a parse failure.

  This rule renames the variable `end` to `result`.

  ## Bad (won't parse)

      def calc(a, b) do
        end = a + b
        end
      end

  ## Good

      def calc(a, b) do
        result = a + b
        result
      end
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches `end` used as a variable name in assignment: `end = ...`
  @assignment_pattern ~r/^(\s*)end\s*=/

  @impl true
  def analyze(source) do
    lines = String.split(source, "\n")
    assignment_lines = find_assignment_lines(lines)

    if assignment_lines != [] do
      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {_line, line_no} ->
        if Enum.any?(assignment_lines, fn {ln, _} -> ln == line_no end) do
          [build_issue(line_no)]
        else
          []
        end
      end)
    else
      []
    end
  end

  @impl true
  def fix(source) do
    lines = String.split(source, "\n")
    assignment_lines = find_assignment_lines(lines)

    if assignment_lines != [] do
      # Get the indentation levels where `end` is used as a variable
      indent_levels = MapSet.new(assignment_lines, fn {_, indent} -> indent end)

      lines
      |> Enum.map_join("\n", fn line ->
        cond do
          # Assignment: `end = expr` -> `result = expr`
          Regex.match?(@assignment_pattern, line) ->
            Regex.replace(~r/\bend\b/, line, "result")

          # Bare `end` at same indentation as an assignment -> `result`
          bare_end_at_indent?(line, indent_levels) ->
            Regex.replace(~r/\bend\b/, line, "result")

          true ->
            line
        end
      end)
    else
      source
    end
  end

  # Find lines where `end` is used as a variable assignment
  # Returns list of {line_number, indentation_string}
  defp find_assignment_lines(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case Regex.run(@assignment_pattern, line) do
        [_, indent] -> [{line_no, indent}]
        _ -> []
      end
    end)
  end

  # Check if a line is a bare `end` at one of the given indentation levels
  defp bare_end_at_indent?(line, indent_levels) do
    case Regex.run(~r/^(\s*)end\s*$/, line) do
      [_, indent] -> MapSet.member?(indent_levels, indent)
      _ -> false
    end
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :no_end_keyword_variable,
      message:
        "`end` is a reserved keyword in Elixir and cannot be used as a variable name. " <>
          "Use `result` instead.",
      meta: %{line: line_no}
    }
  end
end
