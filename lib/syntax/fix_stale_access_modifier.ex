defmodule Credence.Syntax.FixStaleAccessModifier do
  @moduledoc """
  Removes non-Elixir access modifier keywords prepended to `def`/`defp`/`defmacro`/`defmacrop`.

  LLMs translating from Java, Python, or TypeScript sometimes carry over
  access modifiers as prefixes, producing code like `private defp` or
  `static def`. In Elixir, visibility is encoded in the keyword itself
  (`def` = public, `defp` = private), so the prefix is always noise.

  ## Examples

      # Garbled prefix (actual LLM output)
      pprivate defp _calculate_max_product(sorted) do
      # Fixed:
      defp _calculate_max_product(sorted) do

      # Redundant prefix
      private defp helper(x), do: x + 1
      # Fixed:
      defp helper(x), do: x + 1

      # Contradictory prefix (trusts the Elixir keyword)
      private def calculate(x), do: x * 2
      # Fixed:
      def calculate(x), do: x * 2

  The rule always trusts the Elixir keyword and discards the prefix,
  because the function body, tests, and callers are written assuming
  whatever visibility `def`/`defp` provides.

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, not the raw line, so a
  `private def` written inside a heredoc, a string or a comment is invisible to
  the pattern. All three "Examples" above sit in this moduledoc's own heredoc,
  and this rule rewrote all three of them before the shadow was added (docs/22
  T3.10) — quietly deleting the very prefixes the examples exist to show.

  The rewrite reads the real line at the shadow's match offsets, so the bytes
  emitted are always the author's.
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @prefixes ~w(pprivate private public protected static abstract final async pub export)

  @prefix_pattern @prefixes
                  |> Enum.sort_by(&(-String.length(&1)))
                  |> Enum.join("|")

  @line_regex Regex.compile!("^(\\s*)(#{@prefix_pattern})\\s+(defp?|defmacrop?)\\b")

  @impl true
  def analyze(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{line, shadow}, line_no} ->
      case Regex.run(@line_regex, shadow, return: :index) do
        [_match, _indent, {prefix_start, prefix_len}, _def_keyword] ->
          [build_issue(binary_part(line, prefix_start, prefix_len), line_no)]

        nil ->
          []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} -> fix_line(line, shadow) end)
  end

  # The match is located in the shadow and every emitted byte is taken from the
  # real line at those offsets — the two are the same byte length and share every
  # code byte, so the offsets are valid in either. Keeping the indent and the
  # `def` keyword while dropping everything the match covered is the byte-level
  # equivalent of the `"\\1\\3"` replacement this used to do on the raw line.
  defp fix_line(line, shadow) do
    case Regex.run(@line_regex, shadow, return: :index) do
      [{match_start, match_len}, {indent_start, indent_len}, _prefix, {kw_start, kw_len}] ->
        match_end = match_start + match_len

        binary_part(line, indent_start, indent_len) <>
          binary_part(line, kw_start, kw_len) <>
          binary_part(line, match_end, byte_size(line) - match_end)

      nil ->
        line
    end
  end

  defp build_issue(prefix, line_no) do
    %Issue{
      rule: :stale_access_modifier,
      message:
        "`#{prefix}` is not an Elixir keyword — " <>
          "visibility is determined by `def` vs `defp`. Remove the prefix.",
      meta: %{line: line_no}
    }
  end
end
