defmodule Credence.Semantic.FixFnGuardPositionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixFnGuardPosition

  @real_message "cannot find or invoke local when/2 inside a match. Only macros can be invoked inside a match and they must be defined before their invocation. Called as: {[second], count} when second > cutoff"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {27, 25}, file: "credence_check.ex"}
    assert FixFnGuardPosition.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute FixFnGuardPosition.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile module (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixFnGuardPosition.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {27, 25}, file: "credence_check.ex"}
    assert FixFnGuardPosition.to_issue(diag).rule == :fix_fn_guard_position
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}, file: "credence_check.ex"}
    assert FixFnGuardPosition.to_issue(diag).meta.line == 42
  end
end
