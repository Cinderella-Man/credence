defmodule Credence.Syntax.NoPostfixIfExpression do
  @moduledoc """
  Detects and rewrites Python-style postfix `if` expressions.

  LLMs (especially Qwen) emit Python-style postfix `if` (`var = expr if condition`)
  which is a syntax error in Elixir (`syntax error before: 'if'`). This rule
  rewrites it to an idiomatic Elixir `if` expression using the keyword form.

  ## Bad (won't parse)

      new_max = max(current_max, period) if type == :sma

  ## Good

      new_max = if type == :sma, do: max(current_max, period), else: new_max
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches a line containing a Python-style postfix `if` in an assignment:
  #   <indent><var> = <expr> if <condition>
  #
  # Group 1: leading whitespace (indentation)
  # Group 2: LHS variable name
  # Group 3: RHS expression (greedy — matches up to the last ` if `)
  # Group 4: condition (lazy — captures the shortest match after ` if `)
  @postfix_if_pattern ~r/^(\s*)(\w+)\s*=\s*(.+)\s+if\s+(.+?)\s*$/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case parse_postfix_if(line) do
        {:ok, _, _, _, _} ->
          [
            %Issue{
              rule: :no_postfix_if_expression,
              message:
                "Python-style postfix `if` is not valid Elixir. " <>
                  "Use `if condition, do: expr, else: default` instead.",
              meta: %{line: line_no}
            }
          ]

        :error ->
          []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      case parse_postfix_if(line) do
        {:ok, indent, lhs, expr, cond_expr} ->
          "#{indent}#{lhs} = if #{cond_expr}, do: #{expr}, else: #{lhs}"

        :error ->
          line
      end
    end)
  end

  defp parse_postfix_if(line) do
    case Regex.run(@postfix_if_pattern, line, capture: :all_but_first) do
      [indent, lhs, expr, cond_expr] ->
        {:ok, indent, lhs, String.trim_trailing(expr), String.trim_trailing(cond_expr)}

      _ ->
        :error
    end
  end
end
