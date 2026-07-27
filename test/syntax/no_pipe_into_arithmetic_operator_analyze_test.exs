defmodule Credence.Syntax.NoPipeIntoArithmeticOperatorAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoPipeIntoArithmeticOperator

  defp analyze(code), do: NoPipeIntoArithmeticOperator.analyze(code)

  test "flags pipe into division" do
    assert [%Issue{rule: :no_pipe_into_arithmetic_operator}] =
             analyze("list |> Enum.sum() / length(list)")
  end

  test "flags pipe into addition" do
    assert [%Issue{rule: :no_pipe_into_arithmetic_operator}] =
             analyze("x |> foo() + bar()")
  end

  test "flags pipe into subtraction" do
    assert [%Issue{rule: :no_pipe_into_arithmetic_operator}] =
             analyze("x |> foo() - bar()")
  end

  test "flags pipe into multiplication" do
    assert [%Issue{rule: :no_pipe_into_arithmetic_operator}] =
             analyze("x |> foo() * bar()")
  end

  test "leaves valid code alone" do
    assert analyze("Enum.sum(list) / length(list)") == []
  end

  test "leaves valid pipe alone" do
    assert analyze("list |> Enum.sum()") == []
  end
end
