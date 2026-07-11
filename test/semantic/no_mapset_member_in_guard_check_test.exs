defmodule Credence.Semantic.NoMapsetMemberInGuardCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoMapsetMemberInGuard

  @real_message "cannot invoke remote function MapSet.member?/2 inside a guard"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {2, 34}}
    assert NoMapsetMemberInGuard.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoMapsetMemberInGuard.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoMapsetMemberInGuard.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {2, 34}}
    assert NoMapsetMemberInGuard.to_issue(diag).rule == :no_mapset_member_in_guard
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoMapsetMemberInGuard.to_issue(diag).meta.line == 42
  end
end
