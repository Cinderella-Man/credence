defmodule Credence.Syntax.FixTruncatedBinaryClose do
  @moduledoc """
  Fixes truncated binary close delimiters caused by LLM output truncation.

  LLMs repeatedly truncate `<<...::binary>>` to `<<...::binary>)` inside
  nested delimiters (e.g. inside function calls or list constructors).
  This regex-based fix restores the missing `>` character.

  ## Bad (won't parse)

      result = <<first, char, rest::binary>
      [result | insert(char, <<first, rest::binary>)]

  ## Good

      result = <<first, char, rest::binary>>
      [result | insert(char, <<first, rest::binary>>)]

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, not the raw line, so
  string literals, charlists, sigils, heredocs, character literals and comments
  are invisible to the pattern. The pattern is a bare literal with no guard of
  any kind, so without the shadow every mention of the broken delimiter was
  rewritten — `IO.puts("the bug is <<x::binary>)")` gained a `>`, and this rule
  rewrote four lines of its own documentation, which is how it was found.
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches `::binary>)` where the closing `>>` was truncated to `>` then `)`
  # This captures `::binary` followed by one `>` and then `)` instead of `>>`
  @pattern ~r/::binary>\)/

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
  # valid in either. The replacement inserts one `>` before the `)`, so the
  # matched span is rewritten wholesale rather than patched in place.
  defp fix_line(line, shadow) do
    {chunks, pos} =
      @pattern
      |> Regex.scan(shadow, return: :index)
      |> Enum.reduce({[], 0}, fn [{ms, ml}], {acc, pos} ->
        before = binary_part(line, pos, ms - pos)
        {[acc, before, "::binary>>)"], ms + ml}
      end)

    IO.iodata_to_binary([chunks, binary_part(line, pos, byte_size(line) - pos)])
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_truncated_binary_close,
      message: "Truncated binary close delimiter (`::binary>)`) should be `::binary>>)`.",
      meta: %{line: line_no}
    }
  end
end
