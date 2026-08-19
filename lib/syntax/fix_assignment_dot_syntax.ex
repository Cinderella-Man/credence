defmodule Credence.Syntax.FixAssignmentDotSyntax do
  @moduledoc """
  Fixes the extra-dot-after-`=` syntax error LLMs (especially Qwen) produce.

  `var =.function_call()` is a parse-breaking syntax error. The LLM inserts a
  dot between `=` and the function name. The fix removes the spurious dot so
  the assignment becomes `var = function_call()`.

  ## Detected pattern

  A line of the form `<indent><var> =.<identifier>` where `=` is followed
  immediately (or with a single space) by a `.` and then an identifier.

      ref =.make_ref()        →  ref = make_ref()
      x =.some_function(a)    →  x = some_function(a)

  ## Not flagged

  - Valid assignments without the extra dot (`ref = make_ref()`)
  - Comments (`# ref =.make_ref()`)
  - String literals (`msg = "=.not_a_dot"`)
  - A **digit** after the dot (`rate = .05`, `x =.5e3`) — see below

  ## Why a digit after the dot is left alone

  `.5` after `=` is far more likely a Python float literal (`0.5`) than a
  spurious dot before a call: Elixir has no `.5` literal, so the line is
  broken either way, but the two readings disagree about the *value*. Dropping
  the dot turns `rate = .05` into `rate = 05`, which parses — as the integer
  `5`, a different value of a different type — and turns `x =.5e3` into
  `x = 5e3`, which doesn't parse at all. Neither is a same-answer rewrite, so
  the rule requires the character after the dot to start an identifier
  (`a-z`, `A-Z`, `_`). Python-style float literals are a separate problem for
  a separate rule.

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, not the raw line, so
  comments, string literals, sigils, charlists and heredoc bodies are invisible
  to the pattern.

  The "Not flagged" list above used to be true only by accident. The pattern is
  anchored at `^`, so a literal like `msg = "=.not_a_dot"` was missed because the
  `=` is followed by a quote rather than a dot — not because the rule knew it was
  looking at a string. Inside a *heredoc* the accident runs out: the two
  `→` examples in this very moduledoc sit at the start of their lines, and this
  rule rewrote both of them (docs/22 T3.10). The shadow is what actually knows.

  The shadow also subsumes the whole-line comment guard this rule used to carry
  by hand: masking blanks a `#` comment to its last byte, so a commented-out
  assignment cannot match in the first place.

  ## Bad

      ref =.make_ref()
      x = .some_function(a)

  ## Good

      ref = make_ref()
      x = some_function(a)
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Match: optional leading whitespace, a variable name, `=`, an optional space
  # before a dot, then the start of an identifier.  The dot after `=` is the
  # fault.  The lookahead deliberately excludes digits (see the moduledoc).
  # The capture group holds the prefix up to and including `=` (no trailing space)
  # so the callback can append exactly one space.
  @bad_pattern ~r/^(\s*[a-zA-Z_]\w*\s*=)\s?\.(?=[a-zA-Z_])/

  @impl true
  def analyze(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{_line, shadow}, line_no} ->
      if Regex.match?(@bad_pattern, shadow), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} -> fix_line(line, shadow) end)
  end

  # The match is found in the shadow and the bytes are taken from the real line.
  # Both are the same byte length and every code byte is identical, so the
  # offsets are valid in either — and the emitted text is always the author's,
  # never a blanked literal. The pattern is `^`-anchored, so there is at most one
  # match per line and the replacement is a prefix rewrite.
  defp fix_line(line, shadow) do
    case Regex.run(@bad_pattern, shadow, return: :index) do
      [{_match_start, match_len}, {prefix_start, prefix_len}] ->
        binary_part(line, prefix_start, prefix_len) <>
          " " <> binary_part(line, match_len, byte_size(line) - match_len)

      nil ->
        line
    end
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_assignment_dot_syntax,
      message: "Extra dot after `=` in assignment — use `var = fun()` instead of `var =.fun()`.",
      meta: %{line: line_no}
    }
  end
end
