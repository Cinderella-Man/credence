defmodule Credence.Syntax.NoPipeIntoArithmeticOperatorFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoPipeIntoArithmeticOperator

  defp analyze(code), do: NoPipeIntoArithmeticOperator.analyze(code)
  defp fix(code), do: NoPipeIntoArithmeticOperator.fix(code)

  test "fixes pipe into division" do
    input = "list |> Enum.sum() / length(list)"
    expected = "Enum.sum(list) / length(list)"
    confirm_fix(fix(input), expected)
  end

  test "fixes pipe into addition" do
    input = "x |> foo() + bar()"
    expected = "foo(x) + bar()"
    confirm_fix(fix(input), expected)
  end

  test "fixes pipe into subtraction" do
    input = "x |> foo() - bar()"
    expected = "foo(x) - bar()"
    confirm_fix(fix(input), expected)
  end

  test "fixes pipe into multiplication" do
    input = "x |> foo() * bar()"
    expected = "foo(x) * bar()"
    confirm_fix(fix(input), expected)
  end

  test "fixes pipe with multi-arg function call" do
    input = "x |> foo(extra) / bar()"
    expected = "foo(x, extra) / bar()"
    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("list |> Enum.sum() / length(list)")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("list |> Enum.sum() / length(list)"))
  end

  test "leaves clean code unchanged" do
    input = "Enum.sum(list) / length(list)"
    confirm_fix(fix(input), input)
  end
end
