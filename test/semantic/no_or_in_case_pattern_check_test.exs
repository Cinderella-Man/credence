defmodule Credence.Semantic.NoOrInCasePatternCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoOrInCasePattern

  @match_msg "or is not allowed in patterns"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @match_msg, position: {1, 1}}
    assert NoOrInCasePattern.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoOrInCasePattern.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @match_msg, position: {1, 1}}
    assert NoOrInCasePattern.to_issue(diag).rule == :no_or_in_case_pattern
  end
end
