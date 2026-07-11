defmodule Credence.Semantic.NoHallucinatedMathRoundCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedMathRound

  @real_message "misplaced operator ::/2\n\nThe :: operator is typically used in bitstrings to specify types and sizes of segments:\n\n    <<size::32-integer, letter::utf8, rest::binary>>\n\nIt is also used in typespecs, such as @type and @spec, to describe inputs and outputs"

  test "matches the misplaced operator ::/2 diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {121, 55}}
    assert NoHallucinatedMathRound.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedMathRound.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module SharedPoolBucket (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedMathRound.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {121, 55}}
    assert NoHallucinatedMathRound.to_issue(diag).rule == :no_hallucinated_math_round
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoHallucinatedMathRound.to_issue(diag).meta.line == 42
  end
end
