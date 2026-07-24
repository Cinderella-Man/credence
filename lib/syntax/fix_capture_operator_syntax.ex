defmodule Credence.Syntax.FixCaptureOperatorSyntax do
  @moduledoc """
  Fixes capture + comparison operator syntax (`&>`, `&<`, `&>=`, `&<=`).

  LLMs frequently generate `&>`, `&<`, `&>=`, `&<=` (capture + comparison
  operator) intending a function reference. Elixir's capture syntax `&` cannot
  form operators — the parser rejects `&>` with `syntax error before: '>'`.

  The fix rewrites each to its Kernel function capture (`&Kernel.>/2`, etc.).

  ## Bad (won't parse)

      :gt -> &>
      :lt -> &<

  ## Good

      :gt -> &Kernel.>/2
      :lt -> &Kernel.</2

  ## Not flagged

  A bare `&<` / `&>` scan is not safe: the source reaching this phase fails to
  parse *somewhere*, but the rest of the file is ordinary valid Elixir that must
  survive untouched. Two valid shapes contain those exact two bytes:

      Enum.map(list, &<<&1>>)   — a capture whose body is a bitstring literal
      x = a&&<<1>>              — `&&` followed by a bitstring literal

  Both parse today, and rewriting either produces code that no longer parses. So
  the match is pinned to the position where the malformed capture — and nothing
  else — can occur: the `&` must *start* a term (line start, or after whitespace
  or one of `(`, `[`, `{`, `,`) and the operator must be *followed* by a
  delimiter or the end of the line. `&<<` and `&&<<` fail both halves of that.

  Comment lines, heredoc bodies, and text inside a double-quoted string are
  skipped as well, so prose mentioning `&>` keeps its bytes.
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # `&` + comparison operator, in the only position where it can be the
  # malformed capture (see "Not flagged" above). The leading boundary is
  # consumed, not a lookbehind, so the alternation may include `^`; the trailing
  # guard is a lookahead so two captures can sit side by side (`[&>, &<]`).
  # `>=`/`<=` come first so `&>=` never matches as `&>` plus a stray `=`.
  @capture_pattern ~r/(?:^|[\s(\[{,])&(>=|<=|>|<)(?=[\s,)\]}]|$)/

  @impl true
  def analyze(source) do
    source
    |> eligible_lines()
    |> Enum.flat_map(fn {line, line_no, eligible?} ->
      if eligible?,
        do: Enum.map(captures(line), fn {_start, _len, op} -> build_issue(op, line_no) end),
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

  # Every eligible `&op` on the line, as `{byte offset of the &, byte length of
  # `&op`, op}`, in source order.
  defp captures(line) do
    @capture_pattern
    |> Regex.scan(line, return: :index)
    |> Enum.map(fn [_full, {op_start, op_len}] ->
      {op_start - 1, op_len + 1, binary_part(line, op_start, op_len)}
    end)
    |> Enum.reject(fn {start, _len, _op} -> inside_string?(line, start) end)
  end

  # Splice right-to-left so each replacement leaves the offsets of the ones
  # still to come untouched.
  defp fix_line(line) do
    line
    |> captures()
    |> Enum.reverse()
    |> Enum.reduce(line, fn {start, len, op}, acc ->
      binary_part(acc, 0, start) <>
        "&Kernel.#{op}/2" <>
        binary_part(acc, start + len, byte_size(acc) - start - len)
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

  defp build_issue(op, line) do
    %Issue{
      rule: :fix_capture_operator_syntax,
      message:
        "Capture syntax `&#{op}` is not valid in Elixir. " <>
          "Use `&Kernel.#{op}/2` for a function reference instead.",
      meta: %{line: line}
    }
  end
end
