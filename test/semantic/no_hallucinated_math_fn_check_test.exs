defmodule Credence.Semantic.NoHallucinatedMathFnCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedMathFn

  test "matches the :math.min/2 diagnostic" do
    diag = %{severity: :warning, message: ":math.min/2 is undefined or private. Did you mean:\n\n    * sin/1\n", position: {3, 11}}
    assert NoHallucinatedMathFn.match?(diag)
  end

  test "matches the :math.max/2 diagnostic" do
    diag = %{severity: :warning, message: ":math.max/2 is undefined or private", position: {3, 11}}
    assert NoHallucinatedMathFn.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedMathFn.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module SharedPoolBucket (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedMathFn.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: ":math.min/2 is undefined or private", position: {3, 11}}
    assert NoHallucinatedMathFn.to_issue(diag).rule == :no_hallucinated_math_fn
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: ":math.min/2 is undefined or private", position: {42, 10}}
    assert NoHallucinatedMathFn.to_issue(diag).meta.line == 42
  end
end
