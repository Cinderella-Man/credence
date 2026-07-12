defmodule Credence.Semantic.NoRemoteFunctionInGuardCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoRemoteFunctionInGuard

  @real_message "cannot invoke remote function System.monotonic_time/1 inside a guard"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {93, 20}, file: "credence_check.ex"}
    assert NoRemoteFunctionInGuard.match?(diag)
  end

  test "matches DateTime.utc_now diagnostic" do
    diag = %{severity: :error, message: "cannot invoke remote function DateTime.utc_now/0 inside a guard", position: {5, 10}}
    assert NoRemoteFunctionInGuard.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoRemoteFunctionInGuard.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoRemoteFunctionInGuard.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {93, 20}, file: "credence_check.ex"}
    assert NoRemoteFunctionInGuard.to_issue(diag).rule == :no_remote_function_in_guard
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}, file: "credence_check.ex"}
    assert NoRemoteFunctionInGuard.to_issue(diag).meta.line == 42
  end

  test "ignores invalid syntax diagnostic from broken hash-rocket fix output" do
    diag = %{
      severity: :error,
      message: "invalid syntax found on credence_check.ex:98:41:\n    error: syntax error before: '=>'\n    │\n 98 │     do: if(String.length(name) > 0, :do => :ok, :else => {:error, :invalid_name})\n    │                                         ^\n    │\n    └─ credence_check.ex:98:41",
      position: 98,
      file: "credence_check.ex"
    }

    refute NoRemoteFunctionInGuard.match?(diag)
  end
end
