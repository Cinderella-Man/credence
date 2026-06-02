defmodule Credence.Syntax.FixScientificNotation do
  @moduledoc """
  Fixes Python-style scientific notation that is invalid in Elixir.

  LLMs frequently translate Python's `1e-10` notation directly, but Elixir
  requires a decimal point before the exponent: `1.0e-10`.

  ## Bad (won't parse)

      assert_in_delta result, 0.5, 1e-10

  ## Good

      assert_in_delta result, 0.5, 1.0e-10
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches bare integer followed by e/E and exponent, but NOT preceded by a dot
  # (which would mean it already has a decimal part like 1.5e-10) or a digit
  # (which would mean the match is a suffix of a larger number like 123.456e7).
  @pattern ~r/(?<![.\d])(\d+)[eE]([+-]?\d+)/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      trimmed = String.trim(line)

      if not String.starts_with?(trimmed, "#") and Regex.match?(@pattern, line) do
        [build_issue(line_no)]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &fix_line/1)
  end

  defp fix_line(line) do
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, "#") do
      line
    else
      Regex.replace(@pattern, line, "\\1.0e\\2")
    end
  end

  defp build_issue(line) do
    %Issue{
      rule: :python_scientific_notation,
      message:
        "Python-style scientific notation (`1e-10`) is invalid in Elixir. " <>
          "Use `1.0e-10` (with a decimal point) instead.",
      meta: %{line: line}
    }
  end
end
