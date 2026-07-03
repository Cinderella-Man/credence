defmodule Credence.Syntax.PreferDivFunctionOverInfixFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferDivFunctionOverInfix

  defp analyze(code), do: PreferDivFunctionOverInfix.analyze(code)
  defp fix(code), do: PreferDivFunctionOverInfix.fix(code)

  test "fixes simple infix div" do
    input = "a div b"

    expected = "div(a, b)"

    confirm_fix(fix(input), expected)
  end

  test "fixes infix div in function definition" do
    input = "def divide(a, b), do: a div b"

    expected = "def divide(a, b), do: div(a, b)"

    confirm_fix(fix(input), expected)
  end

  test "fixes infix rem" do
    input = "a rem b"

    expected = "rem(a, b)"

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("def divide(a, b), do: a div b")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("def divide(a, b), do: a div b"))
  end

  test "does not modify valid function call syntax" do
    source = "def divide(a, b), do: div(a, b)"

    confirm_fix(fix(source), source)
  end
end
