defmodule Credence.Semantic.NoUnreachableCatchAfterRescueCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUnreachableCatchAfterRescue

  @real_message "this catch clause cannot match because a rescue catch-all already handles it"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {8, 5}}
    assert NoUnreachableCatchAfterRescue.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUnreachableCatchAfterRescue.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {8, 5}}
    assert NoUnreachableCatchAfterRescue.to_issue(diag).rule == :no_unreachable_catch_after_rescue
  end

  test "issue message is the diagnostic message" do
    diag = %{severity: :warning, message: @real_message, position: {8, 5}}
    assert NoUnreachableCatchAfterRescue.to_issue(diag).message == @real_message
  end

  test "issue meta contains the line" do
    diag = %{severity: :warning, message: @real_message, position: {8, 5}}
    assert NoUnreachableCatchAfterRescue.to_issue(diag).meta.line == 8
  end
end
