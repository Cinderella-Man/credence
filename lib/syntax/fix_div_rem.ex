defmodule Credence.Syntax.FixDivRem do
  @moduledoc """
  Fixes `div` and `rem` used as infix operators (Python `//` and `%` style).

  LLMs frequently translate Python's `//` operator as `expr div expr`,
  but `div` is not an infix operator in Elixir — it must be called as
  `div(expr, expr)` or piped as `expr |> div(expr)`.

  ## Bad (won't parse)

      expected_sum = n * (n + 1) div 2

  ## Good

      expected_sum = div(n * (n + 1), 2)
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @operators ~w(div rem)

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      Enum.flat_map(@operators, fn op ->
        if infix_use?(line, op) do
          [build_issue(op, line_no)]
        else
          []
        end
      end)
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &fix_line/1)
  end

  defp infix_use?(line, op) do
    trimmed = String.trim(line)

    not String.starts_with?(trimmed, "#") and
      Regex.match?(infix_pattern(op), line)
  end

  # Matches: word/paren/digit SPACE div/rem SPACE word/digit
  # Does NOT match: |> div(, div(, .div
  defp infix_pattern(op) do
    ~r"(?<![|>.])\b\S+\)\s+#{op}\s+\w|(?<![|>.])\b\w+\s+#{op}\s+\w"
  end

  defp fix_line(line) do
    Enum.reduce(@operators, line, fn op, current ->
      if infix_use?(current, op) and not infix_in_capture?(current, op) do
        rewrite_infix(current, op)
      else
        current
      end
    end)
  end

  # Returns true if the infix usage of `op` is inside a capture &(...)
  # The regex-based rewrite cannot handle capture context correctly,
  # so we skip the fix in that case (the issue is still reported by analyze).
  defp infix_in_capture?(line, op) do
    case Regex.run(~r/\s+#{op}\s+/, line, return: :index) do
      [{pos, _len}] ->
        prefix = String.slice(line, 0, pos)
        in_capture?(prefix)

      _ ->
        false
    end
  end

  defp in_capture?(prefix), do: do_in_capture?(prefix, [])

  defp do_in_capture?("", stack), do: :capture in stack

  defp do_in_capture?(<<?&, ?(, rest::binary>>, stack),
    do: do_in_capture?(rest, [:capture | stack])

  defp do_in_capture?(<<?(, rest::binary>>, stack), do: do_in_capture?(rest, [:regular | stack])
  defp do_in_capture?(<<?), rest::binary>>, [_ | stack]), do: do_in_capture?(rest, stack)
  defp do_in_capture?(<<?), _rest::binary>>, []), do: do_in_capture?([], [])
  defp do_in_capture?(<<_, rest::binary>>, stack), do: do_in_capture?(rest, stack)

  # Rewrites `prefix left_expr div right_expr` → `prefix div(left_expr, right_expr)`
  #
  # Strategy: find the assignment prefix (if any), then split on ` div `.
  # Left operand = everything between `=` (or line start) and the operator.
  # Right operand = everything after the operator to end of expression.
  defp rewrite_infix(line, op) do
    pattern = ~r/^(\s*(?:\w+\s*=\s*)?)(.+?)\s+#{op}\s+(.+?)(\s*$)/

    case Regex.run(pattern, line) do
      [_full, prefix, left, right, trailing] ->
        "#{prefix}#{op}(#{String.trim(left)}, #{String.trim(right)})#{trailing}"

      nil ->
        line
    end
  end

  defp build_issue(op, line) do
    %Issue{
      rule: :"infix_#{op}",
      message:
        "`#{op}` cannot be used as an infix operator in Elixir. " <>
          "Use `#{op}(a, b)` function call syntax instead.",
      meta: %{line: line}
    }
  end
end
