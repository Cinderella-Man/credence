defmodule Credence.Syntax.FixPythonModulo do
  @moduledoc """
  Replaces Python's `%` modulo operator with Elixir's `rem/2`.

  LLMs translating from Python carry over the `%` infix operator for
  modulo arithmetic. In Elixir, `%` is used for maps and structs, not
  arithmetic — the modulo function is `rem/2` (or `Integer.mod/2` for
  floor-division semantics).

  This is a Syntax rule because `a % b` won't parse in Elixir.

  ## Detected patterns

      year % 4          n % 2 == 0
      n % divisor       100 % 7

  Any `word % word` where `%` is used as an infix operator between two
  identifiers or integers.

  ## Not flagged

  Legitimate Elixir `%` usage is not affected:

      %{key: value}           — map literal
      %MyStruct{field: val}   — struct literal
      %{map | key: new}       — map update

  Float operands (`n % 2.0`) are skipped because `rem/2` only accepts
  integers. Comment lines are also skipped.

  ## Bad

      def leap_year?(year) when year % 4 != 0, do: false
      def even?(n), do: n % 2 == 0

  ## Good

      def leap_year?(year) when rem(year, 4) != 0, do: false
      def even?(n), do: rem(n, 2) == 0
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches word % word where the second word is NOT followed by a dot
  # (prevents matching n % 2.0 which would produce broken rem(n, 2).0).
  # Safe against maps/structs because %{ and %Struct{ never have \w+ before %.
  @modulo_pattern ~r/(\w+)\s*%\s*(\w+)(?!\.)/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if modulo_line?(line), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map(fn line ->
      if modulo_line?(line), do: fix_line(line), else: line
    end)
    |> Enum.join("\n")
  end

  # ── Detection ──────────────────────────────────────────────────

  defp modulo_line?(line) do
    not comment?(line) and Regex.match?(@modulo_pattern, line)
  end

  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)

  # ── Fix ────────────────────────────────────────────────────────

  defp fix_line(line) do
    Regex.replace(@modulo_pattern, line, "rem(\\1, \\2)")
  end

  # ── Issue ──────────────────────────────────────────────────────

  defp build_issue(line_no) do
    %Issue{
      rule: :python_modulo,
      message:
        "Python's `%` operator does not exist in Elixir. " <>
          "Use `rem(a, b)` for modulo arithmetic.",
      meta: %{line: line_no}
    }
  end
end
