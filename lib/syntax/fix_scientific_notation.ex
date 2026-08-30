defmodule Credence.Syntax.FixScientificNotation do
  @moduledoc """
  Fixes Python-style scientific notation that is invalid in Elixir.

  LLMs frequently translate Python's `1e-10` notation directly, but Elixir
  requires a decimal point before the exponent: `1.0e-10`.

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, not the raw line, so
  string literals, charlists, sigils, heredocs, character literals and comments
  are invisible to the pattern. Without that, this rule rewrote the inside of
  strings — `IO.puts("version 1e5 build")` became
  `IO.puts("version 1.0e5 build")`, which parses *and* compiles, so nothing
  downstream noticed that the program had started printing something the author
  never wrote.

  The whole-line `#` guard it used before caught only a line that *began* with a
  comment. A trailing comment was rewritten with the code: `x = 1e5 # bump to
  1e9 later` became `x = 1.0e5 # bump to 1.0e9 later`. The shadow blanks a
  comment wherever it starts.

  Interpolation is the exception: `\#{1e5}` is real code and is still fixed.

  ## Bad (won't parse)

      assert_in_delta result, 0.5, 1e-10

  ## Good

      assert_in_delta result, 0.5, 1.0e-10
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches bare integer followed by e/E and exponent, but not when it is part
  # of another token, such as a decimal, hexadecimal literal, or identifier.
  @pattern ~r/(?<![.\p{L}\p{N}_])(\d+)[eE]([+-]?\d+)(?![\p{L}\p{N}_])/u

  @impl true
  def analyze(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{_line, shadow}, line_no} ->
      if Regex.match?(@pattern, shadow), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} -> fix_line(line, shadow) end)
  end

  # Matches are found in the shadow and spliced into the real line. Both are the
  # same byte length and every code byte is identical, so the match offsets are
  # valid in either. `Regex.replace/3` cannot be used here: it would rewrite the
  # shadow, and the shadow is not the file.
  defp fix_line(line, shadow) do
    {chunks, pos} =
      @pattern
      |> Regex.scan(shadow, return: :index)
      |> Enum.reduce({[], 0}, fn [{ms, ml}, {ds, dl}, {es, el}], {acc, pos} ->
        before = binary_part(line, pos, ms - pos)
        digits = binary_part(line, ds, dl)
        exponent = binary_part(line, es, el)
        # ".0e" is written literally, which also normalises `1E5` to `1.0e5`.
        {[acc, before, digits, ".0e", exponent], ms + ml}
      end)

    IO.iodata_to_binary([chunks, binary_part(line, pos, byte_size(line) - pos)])
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
