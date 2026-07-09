defmodule Credence.Syntax.NoPostfixIfExpressionAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoPostfixIfExpression

  defp analyze(code), do: NoPostfixIfExpression.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_postfix_if_expression}] =
             analyze("new_max = max(current_max, period) if type == :sma")
  end

  test "leaves good code alone" do
    assert analyze("new_max = if type == :sma, do: max(current_max, period), else: current_max") ==
             []
  end
end
