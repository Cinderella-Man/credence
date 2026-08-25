defmodule Credence.Syntax.FixPythonModulo do
  @moduledoc """
  Replaces Python's `%` modulo operator with Elixir's `Integer.mod/2`.

  LLMs translating from Python carry over the `%` infix operator for
  modulo arithmetic. In Elixir, `%` is used for maps and structs, not
  arithmetic — the modulo function is `Integer.mod/2`, which has the same
  floor-division semantics as Python's operator.

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

  Float operands (`n % 2.0`) are skipped because `Integer.mod/2` only accepts
  integers.

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, not the raw line, so
  string literals, charlists, sigils, heredocs, character literals and comments
  are invisible to the pattern. Without that, this rule rewrote the inside of
  strings — `IO.puts("100% done")` became `IO.puts("Integer.mod(100, done)")`, which
  parses *and* compiles, so nothing downstream noticed that the program had
  started printing something the author never wrote.

  Interpolation is the exception: `\#{n % 2}` is real code and is still fixed.

  ## Precedence — why some lines are declined

  Python's `%` shares precedence with `*` and `/` and is left-associative, so
  `a * b % 2` means `(a * b) % 2`. Rewriting only the immediate operands would
  emit `a * Integer.mod(b, 2)` — which parses, compiles, and quietly computes a
  different number. Rather than guess at the grouping, a match whose left
  operand is preceded by `*`, `/` or `%` is left alone: the file keeps its
  parse error, which is a loud failure instead of a silent wrong answer.

  `+` and `-` bind *looser* than `%` in Python, so `a + b % 2` really does mean
  `a + (b % 2)` and is still repaired.

  ## Bad

      def leap_year?(year) when year % 4 != 0, do: false
      def even?(n), do: n % 2 == 0

  ## Good

      def leap_year?(year) when Integer.mod(year, 4) != 0, do: false
      def even?(n), do: Integer.mod(n, 2) == 0
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # word % word, where the right operand is not followed by `.` or `{`.
  #
  #   `.` — `n % 2.0` would otherwise become the broken `Integer.mod(n, 2).0`.
  #   `{` — `assert %Issue{} = issue` is a STRUCT literal, and the leading
  #         `assert` supplies the `\w+` the pattern needs. Without this guard
  #         it became `Integer.mod(assert, Issue){} = issue`. Bare `%{...}` and a
  #         struct at the start of an expression were always safe (no `\w+`
  #         precedes the `%`); it is only the call-argument position that bites.
  #
  # The right operand is POSSESSIVE (`\w++`). A plain `\w+` hands characters
  # back to satisfy the lookahead, so `Issue{` matched as `Issu` + `e{` and the
  # guard did nothing — `assert %Issue{}` became `Integer.mod(assert, Issu)e{}`, worse
  # than the bug it was meant to prevent. Possessive matching refuses to give
  # the `e` back, so the whole match fails and the line is left alone.
  @modulo_pattern ~r/-?\w+(?:\s*%\s*\w++(?![.{]))+/

  # Left-hand operators that share or exceed `%`'s precedence in Python.
  @precedence_hazard [?*, ?/, ?%]

  @impl true
  def analyze(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{_line, shadow}, line_no} ->
      if fixable_matches(shadow) == [], do: [], else: [build_issue(line_no)]
    end)
  end

  @impl true
  def fix(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} -> fix_line(line, shadow) end)
  end

  # Matches are found in the shadow and spliced into the real line. Both are
  # the same byte length and every code byte is identical, so the match offsets
  # are valid in either.
  defp fixable_matches(shadow) do
    @modulo_pattern
    |> Regex.scan(shadow, return: :index)
    |> Enum.map(&hd/1)
    |> Enum.reject(fn {match_start, _match_length} ->
      precedence_hazard?(shadow, match_start)
    end)
  end

  defp precedence_hazard?(shadow, left_start) do
    shadow
    |> binary_part(0, left_start)
    |> String.trim_trailing()
    |> String.last()
    |> case do
      nil -> false
      <<c>> -> c in @precedence_hazard
      _ -> false
    end
  end

  defp fix_line(line, shadow) do
    {chunks, pos} =
      shadow
      |> fixable_matches()
      |> Enum.reduce({[], 0}, fn {ms, ml}, {acc, pos} ->
        before = binary_part(line, pos, ms - pos)
        expression = binary_part(line, ms, ml)

        replacement =
          expression
          |> String.split("%")
          |> Enum.map(&String.trim/1)
          |> Enum.reduce(fn right, left -> "Integer.mod(#{left}, #{right})" end)

        {[acc, before, replacement], ms + ml}
      end)

    IO.iodata_to_binary([chunks, binary_part(line, pos, byte_size(line) - pos)])
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :python_modulo,
      message:
        "Python's `%` operator does not exist in Elixir. " <>
          "Use `Integer.mod(a, b)` for modulo arithmetic.",
      meta: %{line: line_no}
    }
  end
end
