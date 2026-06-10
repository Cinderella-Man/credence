defmodule Credence.Semantic.AvoidRemoteFunctionInGuardCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.AvoidRemoteFunctionInGuard

  test "matches the diagnostic" do
    diag = %{
      severity: :error,
      message: "cannot invoke remote function MapSet.size/1 inside a guard",
      position: {2, 75}
    }

    assert AvoidRemoteFunctionInGuard.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute AvoidRemoteFunctionInGuard.match?(diag)
  end

  test "ignores error diagnostics without remote function guard message" do
    diag = %{severity: :error, message: "some other error", position: {1, 1}}
    refute AvoidRemoteFunctionInGuard.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :error,
      message: "cannot invoke remote function MapSet.size/1 inside a guard",
      position: {2, 75}
    }

    assert AvoidRemoteFunctionInGuard.to_issue(diag).rule == :avoid_remote_function_in_guard
  end

  test "to_issue includes the line number from the diagnostic" do
    diag = %{
      severity: :error,
      message: "cannot invoke remote function MapSet.size/1 inside a guard",
      position: {5, 10}
    }

    issue = AvoidRemoteFunctionInGuard.to_issue(diag)
    assert issue.meta.line == 5
  end
end
