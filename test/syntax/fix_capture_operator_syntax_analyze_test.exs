defmodule Credence.Syntax.FixCaptureOperatorSyntaxAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixCaptureOperatorSyntax

  defp analyze(code), do: FixCaptureOperatorSyntax.analyze(code)

  test "flags &>" do
    assert [%Issue{rule: :fix_capture_operator_syntax, message: message}] =
             analyze(":gt -> &>")

    assert message =~ "&>"
  end

  test "flags &<" do
    assert [%Issue{rule: :fix_capture_operator_syntax, message: message}] =
             analyze(":lt -> &<")

    assert message =~ "&<"
  end

  test "flags &>=" do
    assert [%Issue{rule: :fix_capture_operator_syntax, message: message}] =
             analyze(":gte -> &>=")

    assert message =~ "&>="
  end

  test "flags &<=" do
    assert [%Issue{rule: :fix_capture_operator_syntax, message: message}] =
             analyze(":lte -> &<=")

    assert message =~ "&<="
  end

  test "flags multiple capture operators in source" do
    source = """
    case op_name do
      :gt -> &>
      :lt -> &<
      :gte -> &>=
      :lte -> &<=
    end
    """

    issues = analyze(source)
    assert length(issues) == 4
  end

  test "leaves valid Kernel captures alone" do
    source = """
    case op_name do
      :gt -> &Kernel.>/2
      :lt -> &Kernel.</2
    end
    """

    assert analyze(source) == []
  end

  test "leaves good code alone" do
    assert analyze("def foo(x), do: x + 1") == []
  end

  test "leaves capture with valid syntax alone" do
    assert analyze("Enum.map(list, &(&1 + 1))") == []
  end
end
