defmodule Credence.Syntax.FixPythonFloorDiv do
  @moduledoc """
  Replaces Python's `//` floor-division operator with Elixir's `div/2`.

  LLMs translating from Python carry over the `//` operator for integer
  division. In Elixir, `//` is not a valid arithmetic operator (it only
  exists as the range step operator, `first..last//step`), so `a // b`
  does not parse. The integer-division function is `div/2`.

  This is a Syntax rule because `a // b` won't parse in Elixir.

  ## Detected patterns

      a // b            n // 2
      100 // 7          acc |> Kernel.//(k)
      Kernel.//(a, b)

  Any `word // word` where `//` is an infix operator between two identifiers
  or integers, plus the qualified `Kernel.//` call form.

  ## Not flagged

  Legitimate uses of `//` are not affected:

      # // in comments              — comment lines are skipped
      Enum.slice(list, 0..-2//1)    — range step syntax `first..last//step`
      Kernel./(a, b)                — single `/` is float division

  Only `word // word` is rewritten. A `//` whose left operand is a
  parenthesised expression (`(x + y) // 3`) is left untouched — rewriting it
  safely needs a parser, which is unavailable for unparseable source.

  ## Note on semantics

  `div/2` truncates toward zero, matching the way these LLM translations are
  used (the same convention as the sibling `%` → `rem/2` rule). It is *not*
  bit-identical to Python's floor `//` for negative operands; use
  `Integer.floor_div/2` if exact Python floor semantics are required.

  ## Bad

      def half(n), do: n // 2
      acc |> Kernel.//(k) |> do_step()

  ## Good

      def half(n), do: div(n, 2)
      acc |> div(k) |> do_step()
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Qualified floor-division call: `Kernel.//(...)` → `div(...)`.
  @kernel_pattern ~r/Kernel\s*\.\s*\/\//

  # Infix `word // word`. Local two-operand swap (mirrors the `%` → `rem` rule):
  # rewriting only the immediate operands keeps surrounding code intact and
  # never engulfs neighbouring tokens.
  @infix_pattern ~r/(\w+)\s*\/\/\s*(\w+)/

  # Elixir range step syntax: `first..last//step` (e.g. `0..-2//1`, `1..10//2`).
  # The `//` belongs to the range operator, not Python floor division, so the
  # whole line is skipped to avoid rewriting it.
  @range_step_pattern ~r/\.\.[\w\-]*\/\//

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if floor_div_line?(line), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if floor_div_line?(line), do: fix_line(line), else: line
    end)
  end

  # `check` and `fix` share this one predicate, so they never disagree.
  defp floor_div_line?(line) do
    not comment?(line) and not range_step_syntax?(line) and
      (Regex.match?(@kernel_pattern, line) or Regex.match?(@infix_pattern, line))
  end

  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)

  defp range_step_syntax?(line), do: Regex.match?(@range_step_pattern, line)

  defp fix_line(line) do
    line
    |> fix_kernel()
    |> fix_infix()
  end

  # `Kernel.//` → `div`, for both pipe and standalone contexts:
  #   `|> Kernel.//(k)` → `|> div(k)`
  #   `Kernel.//(a, b)` → `div(a, b)`
  defp fix_kernel(line), do: Regex.replace(@kernel_pattern, line, "div")

  # `left // right` → `div(left, right)`, one occurrence at a time.
  defp fix_infix(line), do: Regex.replace(@infix_pattern, line, "div(\\1, \\2)")

  defp build_issue(line_no) do
    %Issue{
      rule: :python_floor_div,
      message:
        "Python's `//` operator does not exist in Elixir. " <>
          "Use `div(a, b)` for integer division.",
      meta: %{line: line_no}
    }
  end
end
