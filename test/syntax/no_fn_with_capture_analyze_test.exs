defmodule Credence.Syntax.NoFnWithCaptureAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoFnWithCapture

  defp analyze(code), do: NoFnWithCapture.analyze(code)

  test "flags fn-keyword mixed with capture syntax" do
    assert [%Issue{rule: :no_fn_with_capture, meta: %{line: 1}}] =
             analyze("Enum.filter(list, fn(&1 > 0))")
  end

  test "reports the line of the offending fn(" do
    assert [%Issue{rule: :no_fn_with_capture, meta: %{line: 2}}] =
             analyze("""
             defmodule Solution do
               def filter_positives(list), do: Enum.filter(list, fn(&1 > 0))
             end
             """)
  end

  test "does not flag valid parenthesised fn parameters" do
    assert analyze("Enum.filter(list, fn(x) -> x > 0 end)") == []
  end

  test "does not flag a valid capture" do
    assert analyze("Enum.filter(list, &(&1 > 0))") == []
  end

  test "does not flag an identifier that merely ends in fn" do
    assert analyze("myfn(&1 > 0)") == []
  end

  test "does not flag the pattern inside a comment line" do
    assert analyze("# Enum.filter(list, fn(&1 > 0))") == []
  end
end
