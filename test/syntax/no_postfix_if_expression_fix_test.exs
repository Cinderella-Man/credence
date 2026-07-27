defmodule Credence.Syntax.NoPostfixIfExpressionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoPostfixIfExpression

  defp analyze(code), do: NoPostfixIfExpression.analyze(code)
  defp fix(code), do: NoPostfixIfExpression.fix(code)

  test "fixes the syntax error" do
    input = "new_max = max(current_max, period) if type == :sma"

    expected = "new_max = if type == :sma, do: max(current_max, period), else: new_max"

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("new_max = max(current_max, period) if type == :sma")) == []
  end

  test "fixed output is well-formed (parses)" do
    # the repaired source must be valid Elixir
    assert valid_syntax?(fix("new_max = max(current_max, period) if type == :sma"))
  end
end
