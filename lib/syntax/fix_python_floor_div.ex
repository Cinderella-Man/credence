defmodule Credence.Syntax.FixPythonFloorDiv do
  @moduledoc """
  Replaces Python's `//` floor-division operator with Elixir's `div/2`.

  LLMs translating from Python carry over the `//` operator for integer
  division. In Elixir, `//` is not a valid arithmetic operator — the
  floor-division function is `div/2`.

  ## Detected patterns

      a // b                   n // 2
      (x + y) // 3            Kernel.//(n)
      acc |> Kernel.//(k)     |> Kernel.//(n - 1)

  ## Not flagged

  Legitimate uses of `//` are not affected:

      # // in comments          — comment lines are skipped
      ~r/pattern//flags         — regex with `//` after pattern
      Kernel./(a, b)            — single `/` is float division
      Enum.slice(list, 0..-2//1) — Elixir range step syntax `first..last//step`

  ## Bad

      result = n * (n + 1) // 2
      acc |> Kernel.//(k) |> do_step()

  ## Good

      result = div(n * (n + 1), 2)
      acc |> div(k) |> do_step()
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Detects `Kernel.//` (qualified floor-division call) in source
  @kernel_pattern ~r/Kernel\s*\.\s*\/\//

  # Detects infix `//` between expressions.
  # Matches: word/paren/digit followed by `//` followed by word/paren/digit.
  # Negative lookbehind avoids matching after `|>`, `.`, or `~` (regex sigil).
  @infix_pattern ~r/(?<![|>.~])\b\w[\w)]*\s*\/\/\s*\w/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      cond do
        comment_line?(line) ->
          []

        Regex.match?(@kernel_pattern, line) ->
          [build_issue(line_no)]

        not range_step_syntax?(line) and Regex.match?(@infix_pattern, line) ->
          [build_issue(line_no)]

        true ->
          []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if comment_line?(line) or range_step_syntax?(line) do
        line
      else
        line |> fix_kernel_pattern() |> fix_infix_pattern()
      end
    end)
  end

  defp comment_line?(line), do: Regex.match?(~r/^\s*#/, line)

  # Elixir range step syntax: `first..last//step` (e.g. `0..-2//1`, `1..10//2`)
  # The `//` is part of the range operator, not Python floor division.
  @range_step_pattern ~r/\.\.[\d\-]*\/\//
  defp range_step_syntax?(line), do: Regex.match?(@range_step_pattern, line)

  # `Kernel.//` → `div` — works for both pipe and standalone contexts:
  #   `|> Kernel.//(k)` → `|> div(k)`
  #   `Kernel.//(a, b)` → `div(a, b)`
  defp fix_kernel_pattern(line) do
    Regex.replace(@kernel_pattern, line, "div")
  end

  # `left_expr // right_expr` → `div(left_expr, right_expr)`.
  #
  # Strategy: find `=` prefix (if any), split on ` // `, wrap as `div()`.
  defp fix_infix_pattern(line) do
    pattern = ~r/^(\s*(?:\w+\s*=\s*)?)(.+?)\s*\/\/\s*(.+?)(\s*$)/

    case Regex.run(pattern, line) do
      [_full, prefix, left, right, trailing] ->
        "#{prefix}div(#{String.trim(left)}, #{String.trim(right)})#{trailing}"

      nil ->
        line
    end
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :python_floor_div,
      message:
        "Python's `//` operator does not exist in Elixir. " <>
          "Use `div(a, b)` for integer (floor) division.",
      meta: %{line: line_no}
    }
  end
end
