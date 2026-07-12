defmodule Credence.Semantic.NoHallucinatedMathRound2CheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedMathRound2

  @diagnostic_msg ":math.round/1 is undefined or private. Did you mean:\n\n    * ceil/1\n    * floor/1\n"

  test "matches the :math.round/1 diagnostic" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: {7, 11}}
    assert NoHallucinatedMathRound2.match?(diag)
  end

  test "matches a shorter form of the diagnostic" do
    diag = %{severity: :warning, message: ":math.round/1 is undefined or private", position: {18, 11}}
    assert NoHallucinatedMathRound2.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedMathRound2.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Money (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedMathRound2.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: {7, 11}}
    assert NoHallucinatedMathRound2.to_issue(diag).rule == :no_hallucinated_math_round2
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: {42, 10}}
    assert NoHallucinatedMathRound2.to_issue(diag).meta.line == 42
  end
end
