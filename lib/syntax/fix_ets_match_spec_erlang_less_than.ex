defmodule Credence.Syntax.FixEtsMatchSpecErlangLessThan do
  @moduledoc """
  Replaces the unparseable bare atom `:=<` with the quoted `:"=<"` for
  Erlang-compatible ETS match spec guards.

  LLMs frequently write Erlang's less-than-or-equal as the bare atom `:=<` in
  ETS match spec guards.  In Elixir, `=<` is not a recognised operator, so `:=<`
  is tokenised as the atom `:=` followed by `<` — and in a guard tuple that is a
  syntax error.  The correct Elixir form is the quoted atom `:"=<"`, which maps
  to the Erlang `=<` operator that ETS match specs expect.

  ## Bad (won't parse)

      guards = [{:=<, :"$1", cutoff}]

  ## Good

      guards = [{:"=<", :"$1", cutoff}]

  ## Not flagged

  A bare `:=<` scan is not safe: the source reaching this phase fails to parse
  *somewhere*, but the rest of the file is ordinary valid Elixir that must
  survive untouched. `:=` is a perfectly good atom, so every shape where `<`
  (or `<=`, `<>`) still has a right operand parses today:

      x = :=< y      — `:= < y`
      x = :=<y       — same
      x = :=<= y     — `:= <= y`
      x = :=<>"a"    — `:= <> "a"`

  Rewriting any of them produces code that no longer parses. So the match is
  pinned to the one position where the malformed atom — and nothing else — can
  occur: `:=<` must *start* a term (line start, or after whitespace or one of
  `(`, `[`, `{`, `,`) and be *immediately followed* by `,`, `)`, `]` or `}`.
  There the trailing `<` would be a binary operator with no right operand, so
  those bytes can never be valid Elixir; the readings above all fail the
  trailing guard (they need whitespace or an operand next, not a closer).

  `:=<` at end of line is skipped for the same reason — the operand may simply
  be on the following line.

  Comments, strings, charlists, sigils, and heredoc bodies are skipped as well,
  so prose mentioning `:=<` keeps its bytes.
  """
  use Credence.Syntax.Rule

  alias Credence.{Issue, SourceMask}

  @bad ":=<"
  @good ~s(:"=<")

  # The bare atom in the only position where it cannot be `:=` followed by a
  # comparison (see "Not flagged" above). The leading boundary is consumed, not a
  # lookbehind, so the alternation may include `^`; the trailing guard is a
  # lookahead so two atoms can sit side by side (`[:=<, :=<]`).
  @pattern ~r/(?:^|[\s(\[{,]):=<(?=[,)\]}])/

  @impl true
  def analyze(source) do
    source
    |> SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{_line, shadow}, line_no} ->
      Enum.map(occurrences(shadow), fn _ -> build_issue(line_no) end)
    end)
  end

  @impl true
  def fix(source) do
    source
    |> SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} -> fix_line(line, shadow) end)
  end

  # Every eligible `:=<` on the line, as the byte offset of its `:`, in source
  # order. The match consumes the leading boundary character (if any), so the
  # atom itself starts at the last three bytes of the match.
  defp occurrences(shadow) do
    @pattern
    |> Regex.scan(shadow, return: :index)
    |> Enum.map(fn [{start, len}] -> start + len - byte_size(@bad) end)
  end

  # Splice right-to-left so each replacement leaves the offsets of the ones
  # still to come untouched.
  defp fix_line(line, shadow) do
    shadow
    |> occurrences()
    |> Enum.reverse()
    |> Enum.reduce(line, fn start, acc ->
      len = byte_size(@bad)

      binary_part(acc, 0, start) <>
        @good <> binary_part(acc, start + len, byte_size(acc) - start - len)
    end)
  end

  defp build_issue(line) do
    %Issue{
      rule: :fix_ets_match_spec_erlang_less_than,
      message:
        "Bare atom `:=<` is not valid Elixir. Use `:\"=<\"` for less-than-or-equal in ETS match specs.",
      meta: %{line: line}
    }
  end
end
