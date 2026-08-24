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
  else — can occur: the `&` must *start* a term (line start, or after whitespace,
  one of `(`, `[`, `{`, `,`, `=`, or an arrow's closing `>`) and the operator
  must be *followed* by a delimiter or the end of the line. `&<<` and `&&<<`
  fail both halves of that.

  Comments and literal contents are masked, so prose mentioning `&>` keeps its
  bytes.
  """

  use Credence.Syntax.Rule
  alias Credence.Issue
  alias Credence.SourceMask

  # `&` + comparison operator, in the only position where it can be the
  # malformed capture (see "Not flagged" above). The leading boundary is
  # consumed, not a lookbehind, so the alternation may include `^`; the trailing
  # guard is a lookahead so two captures can sit side by side (`[&>, &<]`).
  # `>=`/`<=` come first so `&>=` never matches as `&>` plus a stray `=`.
  @capture_pattern ~r/(?:^|[\s(\[{,=>])&(>=|<=|>|<)(?=[\s,)\]}]|$)/

  @impl true
  def analyze(source) do
    source
    |> SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{line, shadow}, line_no} ->
      Enum.map(captures(line, shadow), fn {_start, _len, op} -> build_issue(op, line_no) end)
    end)
  end

  @impl true
  def fix(source) do
    source
    |> SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} ->
      fix_line(line, shadow)
    end)
  end

  # Every eligible `&op` on the line, as `{byte offset of the &, byte length of
  # `&op`, op}`, in source order.
  defp captures(line, shadow) do
    @capture_pattern
    |> Regex.scan(shadow, return: :index)
    |> Enum.map(fn [_full, {op_start, op_len}] ->
      {op_start - 1, op_len + 1, binary_part(line, op_start, op_len)}
    end)
  end

  # Splice right-to-left so each replacement leaves the offsets of the ones
  # still to come untouched.
  defp fix_line(line, shadow) do
    captures(line, shadow)
    |> Enum.reverse()
    |> Enum.reduce(line, fn {start, len, op}, acc ->
      binary_part(acc, 0, start) <>
        "&Kernel.#{op}/2" <>
        binary_part(acc, start + len, byte_size(acc) - start - len)
    end)
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
