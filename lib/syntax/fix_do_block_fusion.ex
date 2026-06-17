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
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if not comment?(line) and fused?(line) do
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
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if comment?(line), do: line, else: fix_line(line)
    end)
  end

  # ORDER MATTERS - fixes cascade: `, do do` needs the double collapsed first so the
  # end-of-line rule can then see `, do`; midline `, do expr` is the one-liner form
  defp fix_line(line) do
    line
    |> String.replace(@double_do, "do")
    |> String.replace(@paren_do_colon, "), do: ")
    |> String.replace(@comma_do_eol, " do")
    |> String.replace(@comma_do_midline, ", do: ")
    |> strip_stray_trailing_end()
  end

  defp strip_stray_trailing_end(line) do
    Regex.replace(@do_colon_trailing_end, line, fn whole, prefix, expr ->
      if Regex.match?(@block_keyword, expr), do: whole, else: prefix <> expr
    end)
  end

  defp fused?(line) do
    Regex.match?(@comma_do_eol, line) or Regex.match?(@double_do, line) or
      Regex.match?(@paren_do_colon, line) or Regex.match?(@comma_do_midline, line) or
      stray_trailing_end?(line)
  end

  defp stray_trailing_end?(line) do
    case Regex.run(@do_colon_trailing_end, line) do
      [_whole, _prefix, expr] -> not Regex.match?(@block_keyword, expr)
      _ -> false
    end
  end

  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)
end
