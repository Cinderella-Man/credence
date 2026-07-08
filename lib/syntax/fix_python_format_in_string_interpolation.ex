defmodule Credence.Syntax.FixPythonFormatInStringInterpolation do
  @moduledoc """
  Fixes Python-style format specifiers inside Elixir string interpolation.

  LLMs (especially Qwen) generate Python-style `:0N` format specifiers inside
  `\#{}` interpolation, e.g. `"\#{cents_part:02}"`. This is a deterministic
  SyntaxError in Elixir — the colon after the expression is interpreted as
  invalid keyword syntax.

  The fix replaces `\#{expr:0N}` with
  `\#{String.pad_leading(Integer.to_string(expr), N, "0")}`.

  ## Detected patterns

      "\#{cents_part:02}"         → "\#{String.pad_leading(Integer.to_string(cents_part), 2, "0")}"
      "\#{n:05}"                  → "\#{String.pad_leading(Integer.to_string(n), 5, "0")}"

  Any `\#{identifier:0digits}` inside a string interpolation where the
  identifier is a simple word and the digits specify zero-padding width.

  ## Not flagged

  Legitimate Elixir interpolation is not affected:

      "\#{variable}"              — plain interpolation
      "\#{inspect(map)}"          — function call interpolation
      `%{key: value}`             — map literal (no `#` prefix)

  ## Bad

      "\#{cents_part:02}"

  ## Good

      "\#{String.pad_leading(Integer.to_string(cents_part), 2, "0")}"
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches Python-style format specifier inside string interpolation:
  #   #{identifier:0N}
  # where identifier is a simple word and N is the zero-padding width.
  @format_pattern ~r/#\{(\w+):0(\d+)\}/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if format_line?(line), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if format_line?(line), do: fix_line(line), else: line
    end)
  end

  defp format_line?(line) do
    Regex.match?(@format_pattern, line)
  end

  defp fix_line(line) do
    Regex.replace(@format_pattern, line, fn _match, expr, width ->
      "\#{String.pad_leading(Integer.to_string(#{expr}), #{width}, \"0\")}"
    end)
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_python_format_in_string_interpolation,
      message:
        "Python-style format specifier `:0N` inside \#{ } interpolation is invalid in Elixir. " <>
          "Use `String.pad_leading(Integer.to_string(expr), N, \"0\")` instead.",
      meta: %{line: line_no}
    }
  end
end
