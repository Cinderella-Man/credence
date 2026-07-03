defmodule Credence.Syntax.PreferDivFunctionOverInfix do
  @moduledoc """
  Detects `div` and `rem` used as infix operators and rewrites them
  to function call syntax.

  LLMs frequently use `div` and `rem` as infix operators (borrowed
  from Python or Haskell), but in Elixir they are functions —
  `a div b` does not parse. The correct form is `div(a, b)`.

  ## Bad (won't parse)

      def divide(a, b), do: a div b
      def modulo(a, b), do: a rem b

  ## Good

      def divide(a, b), do: div(a, b)
      def modulo(a, b), do: rem(a, b)
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
        if infix_use?(line, op), do: [build_issue(op, line_no)], else: []
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

  # Matches: word/paren-expr SPACE div/rem SPACE word/paren-expr
  # Does NOT match: |> div(, div(, .div, divide
  defp infix_pattern(op) do
    ~r/\b(\w+|\([^)]*\))\s+\b#{op}\b\s+(\w+|\([^)]*\))/
  end

  defp fix_line(line) do
    Enum.reduce(@operators, line, fn op, current ->
      if infix_use?(current, op) do
        rewrite_infix(current, op)
      else
        current
      end
    end)
  end

  # Rewrites `left op right` → `op(left, right)`.
  defp rewrite_infix(line, op) do
    Regex.replace(infix_pattern(op), line, "#{op}(\\1, \\2)")
  end

  defp build_issue(op, line) do
    %Issue{
      rule: :prefer_div_function_over_infix,
      message:
        "`#{op}` cannot be used as an infix operator in Elixir. " <>
          "Use `#{op}(a, b)` function call syntax instead.",
      meta: %{line: line}
    }
  end
end
