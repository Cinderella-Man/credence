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

  Comment lines, heredoc bodies, and text inside a double-quoted string are
  skipped as well, so prose mentioning `:=<` keeps its bytes.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

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
    |> eligible_lines()
    |> Enum.flat_map(fn {line, line_no, eligible?} ->
      if eligible?,
        do: Enum.map(occurrences(line), fn _ -> build_issue(line_no) end),
        else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> eligible_lines()
    |> Enum.map_join("\n", fn {line, _line_no, eligible?} ->
      if eligible?, do: fix_line(line), else: line
    end)
  end

  # Walks the lines once, carrying heredoc state, and tags each line with
  # whether the rule may touch it. `analyze` and `fix` read the same tag, so
  # `analyze` can never flag a line `fix` refuses to rewrite.
  defp eligible_lines(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_reduce(false, fn {line, line_no}, in_heredoc? ->
      eligible? = not in_heredoc? and not comment?(line)
      {{line, line_no, eligible?}, toggle_heredoc(in_heredoc?, line)}
    end)
    |> elem(0)
  end

  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)

  # Heredoc bodies are prose (`@moduledoc """ … """`), not code. An odd number of
  # `"""` on a line flips the state; a stray delimiter therefore only ever makes
  # the rule skip more, never rewrite more.
  defp toggle_heredoc(in_heredoc?, line) do
    if rem(count_occurrences(line, ~s(""")), 2) == 1, do: not in_heredoc?, else: in_heredoc?
  end

  defp count_occurrences(line, needle) do
    div(byte_size(line) - byte_size(String.replace(line, needle, "")), byte_size(needle))
  end

  # Every eligible `:=<` on the line, as the byte offset of its `:`, in source
  # order. The match consumes the leading boundary character (if any), so the
  # atom itself starts at the last three bytes of the match.
  defp occurrences(line) do
    @pattern
    |> Regex.scan(line, return: :index)
    |> Enum.map(fn [{start, len}] -> start + len - byte_size(@bad) end)
    |> Enum.reject(&inside_string?(line, &1))
  end

  # Splice right-to-left so each replacement leaves the offsets of the ones
  # still to come untouched.
  defp fix_line(line) do
    line
    |> occurrences()
    |> Enum.reverse()
    |> Enum.reduce(line, fn start, acc ->
      len = byte_size(@bad)

      binary_part(acc, 0, start) <>
        @good <> binary_part(acc, start + len, byte_size(acc) - start - len)
    end)
  end

  # True when byte `pos` sits inside a double-quoted string on this line: an odd
  # number of quotes precedes it, once escaped quotes (`\"`) and the character
  # literal `?"` are discounted. Miscounting can only make the rule skip a real
  # target, never rewrite a protected one.
  defp inside_string?(line, pos) do
    prefix =
      line
      |> binary_part(0, pos)
      |> String.replace(~S(\"), "")
      |> String.replace(~S(?"), "")

    rem(count_occurrences(prefix, ~s(")), 2) == 1
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
