defmodule Credence.Syntax.NoFnWithCapture do
  @moduledoc """
  Repairs `fn(&1 ...)` — the `fn` keyword mistakenly mixed with capture syntax.

  LLMs translating from other languages repeatedly emit `fn(&1 > 0)`, gluing the
  `fn` keyword onto a capture body. In Elixir `fn` opens a clause that needs
  `-> body end`, so `fn(&1 ...)` never parses — the compiler reports a mismatched
  delimiter (the `)` arrives where an `end` was expected). It is always a syntax
  error, so this is a REPAIR: the fix rewrites the leading `fn(` to `&(`,
  yielding the idiomatic capture form.

  Only `fn(` immediately followed by a capture variable (`&1`, `&2`, …) is
  touched — `fn(x) -> ... end` (parenthesised parameters) is valid Elixir and a
  capture variable can never legally appear in that position, so the match fires
  exclusively on the malformed shape.

  ## Bad (won't parse)

      Enum.filter(list, fn(&1 > 0))

  ## Good

      Enum.filter(list, &(&1 > 0))

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, not the raw line, so
  comments, strings, sigils and heredoc bodies are invisible to the pattern.

  This rule is the clearest case on the T3.10 ledger that *knowing about the
  failure mode is not the same as being guarded against it*. It already carried a
  hand-written guard, and a comment explaining that rewriting non-code content
  would be corruption — but the guard only skipped lines beginning with `#`, so
  it protected comments and missed heredocs entirely. The prose in this very
  moduledoc names the malformed form four times in backticks, and the rule
  rewrote three of those sentences into describing the *fixed* form, leaving
  documentation that no longer says what it repairs. The shadow covers the whole
  class the original comment was reaching for, so the `#` guard is gone.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # `fn(` (standalone — not the tail of an identifier like `myfn(`) immediately
  # followed by a capture variable (`&1`, `&2`, …).
  @fn_capture_pattern ~r/\bfn\(&[1-9]/

  @impl true
  def analyze(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{_line, shadow}, line_no} ->
      if fn_capture_line?(shadow) do
        [
          %Issue{
            rule: :no_fn_with_capture,
            message:
              "`fn(` followed by a capture variable is a parse error; " <>
                "use `&(...)` capture syntax instead.",
            meta: %{line: line_no}
          }
        ]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} ->
      if fn_capture_line?(shadow), do: fix_line(line, shadow), else: line
    end)
  end

  # `check` and `fix` are asked this same question about the same shadow, so they
  # never disagree — the trap being that a rule masked on one side only fixes
  # what it never reported.
  defp fn_capture_line?(shadow), do: Regex.match?(@fn_capture_pattern, shadow)

  # `fn(` is 3 bytes and becomes the 2-byte `&(`; the capture variable that
  # completes the match is left exactly as written. Matches are located in the
  # shadow and every emitted byte is copied from the real line, which is what
  # keeps an interpolated `\#{fn(&1 > 0)}` — real code inside a literal —
  # repairable while the surrounding string stays untouched.
  defp fix_line(line, shadow) do
    {chunks, pos} =
      @fn_capture_pattern
      |> Regex.scan(shadow, return: :index)
      |> Enum.reduce({[], 0}, fn [{match_start, _match_len}], {acc, pos} ->
        before = binary_part(line, pos, match_start - pos)
        {[acc, before, "&("], match_start + 3}
      end)

    IO.iodata_to_binary([chunks, binary_part(line, pos, byte_size(line) - pos)])
  end
end
