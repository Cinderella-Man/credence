defmodule Credence.Semantic.FixRemoteCallInPatternCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixRemoteCallInPattern

  @real_message "cannot invoke remote function state.ref/0 inside a match"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {4, 14}}
    assert FixRemoteCallInPattern.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixRemoteCallInPattern.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile module Example (errors have been logged)",
      position: 0
    }

    refute FixRemoteCallInPattern.match?(diag)
  end

  test "ignores guard variant (handled by NoRemoteFunctionInGuard)" do
    diag = %{
      severity: :error,
      message: "cannot invoke remote function System.monotonic_time/1 inside a guard",
      position: {1, 1}
    }

    refute FixRemoteCallInPattern.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {4, 14}}
    assert FixRemoteCallInPattern.to_issue(diag).rule == :fix_remote_call_in_pattern
  end

  test "preserves the line in the issue" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert FixRemoteCallInPattern.to_issue(diag).meta.line == 42
  end
end
