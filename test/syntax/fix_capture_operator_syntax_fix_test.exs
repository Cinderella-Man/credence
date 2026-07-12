defmodule Credence.Syntax.FixCaptureOperatorSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixCaptureOperatorSyntax

  defp analyze(code), do: FixCaptureOperatorSyntax.analyze(code)
  defp fix(code), do: FixCaptureOperatorSyntax.fix(code)

  test "fixes &> to &Kernel.>/2" do
    input = ":gt -> &>"
    expected = ":gt -> &Kernel.>/2"

    confirm_fix(fix(input), expected)
  end

  test "fixes &< to &Kernel.</2" do
    input = ":lt -> &<"
    expected = ":lt -> &Kernel.</2"

    confirm_fix(fix(input), expected)
  end

  test "fixes &>= to &Kernel.>=/2" do
    input = ":gte -> &>="
    expected = ":gte -> &Kernel.>=/2"

    confirm_fix(fix(input), expected)
  end

  test "fixes &<= to &Kernel.<=/2" do
    input = ":lte -> &<="
    expected = ":lte -> &Kernel.<=/2"

    confirm_fix(fix(input), expected)
  end

  test "fixes all four capture operators in a case block" do
    input = ~S"""
    case op_name do
      :gt -> &>
      :lt -> &<
      :gte -> &>=
      :lte -> &<=
    end
    """

    expected = ~S"""
    case op_name do
      :gt -> &Kernel.>/2
      :lt -> &Kernel.</2
      :gte -> &Kernel.>=/2
      :lte -> &Kernel.<=/2
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = ":gt -> &>"
    assert analyze(fix(input)) == []
  end

  test "fixed output no longer flags for all operators" do
    source = """
    case op_name do
      :gt -> &>
      :lt -> &<
      :gte -> &>=
      :lte -> &<=
    end
    """

    assert analyze(fix(source)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    case op_name do
      :gt -> &>
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "does not modify valid Kernel captures" do
    source = ":gt -> &Kernel.>/2"
    confirm_fix(fix(source), source)
  end

  test "does not modify pipe operator" do
    source = "x |> foo() |> bar()"
    confirm_fix(fix(source), source)
  end

  test "does not modify capture with other operators" do
    source = "Enum.map(list, &(&1 + 1))"
    confirm_fix(fix(source), source)
  end
end
