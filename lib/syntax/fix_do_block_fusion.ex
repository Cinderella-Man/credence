defmodule Credence.Syntax.FixDoBlockFusion do
  @moduledoc """
  Fixes LLM confusions between the `do ... end` block form and the `, do:`
  one-liner form of definitions.

  Diffusion code models (Dream, DiffuCoder) emit these fusions constantly -
  they are the single most common reason a draft fails to parse.

  ## Detected patterns

      def f(x), do        - comma followed by a block opener at end of line
      def f(x), do expr   - one-liner missing the colon (midline)
      def f(x) do do      - doubled block opener
      def f(x) do: expr   - block opener fused with one-liner syntax
      def f(x), do: expr end - one-liner with a stray trailing `end`

  ## Bad

      def push(stack, value), do
        [value | stack]
      end

      def double(number) do: number * 2 end

  ## Good

      def push(stack, value) do
        [value | stack]
      end

      def double(number), do: number * 2

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, not the raw line, so
  comments, strings, sigils and heredoc bodies are invisible to every stage. All
  five "Detected patterns" above are spelled out in this moduledoc's own heredoc,
  and this rule rewrote them (docs/22 T3.10) — the doc for `def f(x), do` came
  back reading `def f(x) do`, so the line documenting the *input* silently became
  a line documenting the output.

  ## Why the shadow is threaded through the cascade

  The five stages feed each other and each one changes the line's byte length —
  `) do: ` grows to `), do: `, and the stray-`end` stage only ever fires on what
  the `) do:` stage produced. So this rule cannot collect every match up front and
  splice once, and it equally cannot re-mask between stages: masking a line on its
  own cannot see heredoc state that opened on an earlier line, which is exactly
  the defect `FixDivRem` shipped with (docs/22 T3.7).

  Instead the `{line, shadow}` pair is carried through the cascade and **both**
  receive the identical splice at each stage. Every replacement this rule emits is
  pure code, so after each stage the pair is still a valid one — same byte length,
  same code bytes, literals still blanked — and the next stage can match on it.
  """

  use Credence.Syntax.Rule

  @double_do ~r/\bdo[ \t]+do\b/
  @paren_do_colon ~r/\)[ \t]+do:[ \t]/
  @comma_do_eol ~r/,\s*do[ \t]*$/m
  @comma_do_midline ~r/,[ \t]*do[ \t]+(?!do\b)(?=\S)/
  @do_colon_trailing_end ~r/(,[ \t]*do:)([^\n]*?)[ \t]+end[ \t]*$/m

  # A trailing `end` is only stray when the `, do:` expression opens no block of
  # its own. If the expression contains a `do`/`fn`/`end` keyword the `end` may
  # legitimately close an inner block (`, do: case x do _ -> 1 end` is VALID),
  # so stripping it would corrupt working code. Both analyze and fix consult
  # this guard so they agree on which lines are touched.
  @block_keyword ~r/\b(?:do|fn|end)\b/

  @impl true
  def analyze(source) do
    valid_source? = valid_source?(source)

    source
    |> Credence.SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{line, shadow}, line_no} ->
      if fused?(shadow, valid_source?) do
        [
          %Credence.Issue{
            rule: __MODULE__,
            message: "do-block/one-liner fusion: #{String.trim(line)}",
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
    valid_source? = valid_source?(source)

    source
    |> Credence.SourceMask.lines()
    |> Enum.map_join("\n", fn pair -> pair |> fix_line(valid_source?) |> elem(0) end)
  end

  # ORDER MATTERS - fixes cascade: `, do do` needs the double collapsed first so the
  # end-of-line rule can then see `, do`; midline `, do expr` is the one-liner form.
  #
  # The `{line, shadow}` pair moves through the cascade together and each stage
  # splices the same bytes into both — see the moduledoc for why the shadow is
  # carried rather than recomputed between stages.
  defp fix_line(pair, valid_source?) do
    pair
    |> replace_both(@double_do, "do")
    |> replace_both(@paren_do_colon, "), do: ")
    |> replace_both(@comma_do_eol, " do")
    |> replace_both(@comma_do_midline, ", do: ")
    |> strip_stray_trailing_end(valid_source?)
  end

  # Every match is located in the shadow; the identical replacement text is
  # spliced into the real line and into the shadow. The replacement is pure code,
  # so the pair remains a valid one for the next stage.
  defp replace_both({line, shadow}, pattern, replacement) do
    case Regex.scan(pattern, shadow, return: :index) do
      [] -> {line, shadow}
      matches -> {splice(line, matches, replacement), splice(shadow, matches, replacement)}
    end
  end

  defp splice(subject, matches, replacement) do
    {chunks, pos} =
      Enum.reduce(matches, {[], 0}, fn [{match_start, match_len} | _], {acc, pos} ->
        {[acc, binary_part(subject, pos, match_start - pos), replacement],
         match_start + match_len}
      end)

    IO.iodata_to_binary([chunks, binary_part(subject, pos, byte_size(subject) - pos)])
  end

  # The last stage, and the only one whose replacement is not a constant: it drops
  # the trailing ` end` and keeps the bytes before it. The `@block_keyword` guard
  # is asked of the *shadow's* expression, so a `do`/`fn`/`end` appearing inside a
  # string no longer counts as opening a block — while the bytes that survive into
  # the output are the real line's.
  defp strip_stray_trailing_end(pair, true), do: pair

  defp strip_stray_trailing_end({line, shadow}, false) do
    case Regex.run(@do_colon_trailing_end, shadow, return: :index) do
      [{match_start, match_len}, prefix, {expr_start, expr_len} = expr] ->
        if Regex.match?(@block_keyword, binary_part(shadow, expr_start, expr_len)) do
          {line, shadow}
        else
          drop_end = &keep_through_expr(&1, match_start, match_len, prefix, expr)
          {drop_end.(line), drop_end.(shadow)}
        end

      _ ->
        {line, shadow}
    end
  end

  defp keep_through_expr(subject, match_start, match_len, {ps, pl}, {es, el}) do
    match_end = match_start + match_len

    binary_part(subject, 0, match_start) <>
      binary_part(subject, ps, pl) <>
      binary_part(subject, es, el) <>
      binary_part(subject, match_end, byte_size(subject) - match_end)
  end

  defp fused?(shadow, valid_source?) do
    Regex.match?(@comma_do_eol, shadow) or Regex.match?(@double_do, shadow) or
      Regex.match?(@paren_do_colon, shadow) or Regex.match?(@comma_do_midline, shadow) or
      (not valid_source? and stray_trailing_end?(shadow))
  end

  defp valid_source?(source), do: match?({:ok, _}, Sourceror.parse_string(source))

  defp stray_trailing_end?(shadow) do
    case Regex.run(@do_colon_trailing_end, shadow) do
      [_whole, _prefix, expr] -> not Regex.match?(@block_keyword, expr)
      _ -> false
    end
  end
end
