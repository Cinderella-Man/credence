defmodule Credence.Syntax.FixPythonFloorDiv do
  @moduledoc """
  Replaces Python's `//` floor-division operator with Elixir's `div/2`.

  LLMs translating from Python carry over the `//` operator for integer
  division. In Elixir, `//` is not a valid arithmetic operator (it only
  exists as the range step operator, `first..last//step`), so `a // b`
  does not parse. The integer-division function is `div/2`.

  This is a Syntax rule because `a // b` won't parse in Elixir.

  ## Detected patterns

      a // b            n // 2
      100 // 7          acc |> Kernel.//(k)
      Kernel.//(a, b)

  Any `word // word` where `//` is an infix operator between two identifiers
  or integers, plus the qualified `Kernel.//` call form.

  ## Not flagged

  Legitimate uses of `//` are not affected:

      # // in comments              — comments are not code
      Enum.slice(list, 0..-2//1)    — range step syntax `first..last//step`
      Kernel./(a, b)                — single `/` is float division

  Only `word // word` is rewritten. A `//` whose left operand is a
  parenthesised expression (`(x + y) // 3`) is left untouched — rewriting it
  safely needs a parser, which is unavailable for unparseable source.

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, not the raw line, so
  string literals, charlists, sigils, heredocs, character literals and comments
  are invisible to the pattern. Without that, this rule rewrote the inside of
  strings — `IO.puts("ratio 7 // 2 here")` became
  `IO.puts("ratio div(7, 2) here")`, which parses *and* compiles, so nothing
  downstream noticed that the program had started printing something the author
  never wrote.

  The whole-line `^\\s*#` guard it used before caught only a line that *began*
  with a comment. A trailing comment was rewritten with the code:
  `x = a // b  # was a // b` came back as `x = div(a, b)  # was div(a, b)`. The
  shadow blanks a comment wherever it starts.

  Interpolation is the exception: `\#{a // b}` is real code and is still fixed.

  ## Note on semantics

  `div/2` truncates toward zero, matching the way these LLM translations are
  used (the same convention as the sibling `%` → `rem/2` rule). It is *not*
  bit-identical to Python's floor `//` for negative operands; use
  `Integer.floor_div/2` if exact Python floor semantics are required.

  ## Bad

      def half(n), do: n // 2
      acc |> Kernel.//(k) |> do_step()

  ## Good

      def half(n), do: div(n, 2)
      acc |> div(k) |> do_step()
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Qualified floor-division call: `Kernel.//(...)` → `div(...)`.
  @kernel_pattern ~r/Kernel\s*\.\s*\/\//

  # Infix `word // word`. Local two-operand swap (mirrors the `%` → `rem` rule):
  # rewriting only the immediate operands keeps surrounding code intact and
  # never engulfs neighbouring tokens.
  @infix_pattern ~r/(\w+)\s*\/\/\s*(\w+)/

  # Elixir range step syntax: `first..last//step` (e.g. `0..-2//1`, `1..10//2`).
  # The `//` belongs to the range operator, not Python floor division, so the
  # whole line is skipped to avoid rewriting it.
  @range_step_pattern ~r/\.\.[\w\-]*\/\//

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

  # `analyze` and `fix` share this one function, so they never disagree: a line
  # is flagged exactly when this returns a non-empty list, and rewritten exactly
  # where it says.
  #
  # Everything is decided on the shadow. The old whole-line `^\s*#` guard is
  # gone because it is subsumed and was too narrow — it skipped a line that
  # *began* with a comment but rewrote a trailing one, so `x = a // b  # was a
  # // b` came back with the comment rewritten too. In the shadow a comment is
  # blank wherever it starts.
  defp fixable_matches(shadow) do
    if Regex.match?(@range_step_pattern, shadow) do
      []
    else
      kernel =
        @kernel_pattern
        |> Regex.scan(shadow, return: :index)
        |> Enum.map(fn [{s, l}] -> {s, l, :kernel, []} end)

      infix =
        @infix_pattern
        |> Regex.scan(shadow, return: :index)
        |> Enum.map(fn [{s, l}, left, right] -> {s, l, :infix, [left, right]} end)
        |> Enum.reject(fn m -> Enum.any?(kernel, &overlaps?(&1, m)) end)

      Enum.sort_by(kernel ++ infix, fn {s, _l, _kind, _groups} -> s end)
    end
  end

  # The two patterns cannot both own the same bytes. They do not overlap on any
  # shape either rule documents (`Kernel.//` has a `.` where the infix pattern
  # needs `\s*`), but `a // Kernel.//(b)` puts them on top of each other, and
  # applying both there produced `div(a, div)(b)`. The qualified call wins and
  # the infix match is dropped, which leaves the parse error in place rather
  # than emitting something that parses and means something else.
  defp overlaps?({as, al, _, _}, {bs, bl, _, _}), do: as < bs + bl and bs < as + al

  # Matches are found in the shadow and spliced into the real line. Both are the
  # same byte length and every code byte is identical, so the match offsets are
  # valid in either.
  defp fix_line(line, shadow) do
    {chunks, pos} =
      shadow
      |> fixable_matches()
      |> Enum.reduce({[], 0}, fn {ms, ml, kind, groups}, {acc, pos} ->
        before = binary_part(line, pos, ms - pos)
        {[acc, before, replacement(line, kind, groups)], ms + ml}
      end)

    IO.iodata_to_binary([chunks, binary_part(line, pos, byte_size(line) - pos)])
  end

  # `Kernel.//` → `div`, for both pipe and standalone contexts:
  #   `|> Kernel.//(k)` → `|> div(k)`
  #   `Kernel.//(a, b)` → `div(a, b)`
  defp replacement(_line, :kernel, []), do: "div"

  # `left // right` → `div(left, right)`.
  defp replacement(line, :infix, [{ls, ll}, {rs, rl}]),
    do: ["div(", binary_part(line, ls, ll), ", ", binary_part(line, rs, rl), ")"]

  defp build_issue(line_no) do
    %Issue{
      rule: :python_floor_div,
      message:
        "Python's `//` operator does not exist in Elixir. " <>
          "Use `div(a, b)` for integer division.",
      meta: %{line: line_no}
    }
  end
end
