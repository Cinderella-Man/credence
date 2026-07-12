defmodule Credence.Semantic.NoValidationRejectsInfinityForTimeoutCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoValidationRejectsInfinityForTimeout

  @match_msg "must be a positive integer"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @match_msg, position: {1, 1}}
    assert NoValidationRejectsInfinityForTimeout.match?(diag)
  end

  test "matches diagnostic with full raise message" do
    diag = %{severity: :warning, message: ":interval must be a positive integer", position: {1, 1}}
    assert NoValidationRejectsInfinityForTimeout.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoValidationRejectsInfinityForTimeout.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_msg, position: {1, 1}}

    assert NoValidationRejectsInfinityForTimeout.to_issue(diag).rule ==
             :no_validation_rejects_infinity_for_timeout
  end
end
