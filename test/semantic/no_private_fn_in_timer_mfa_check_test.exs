defmodule Credence.Semantic.NoPrivateFnInTimerMfaCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoPrivateFnInTimerMfa

  # The real captured diagnostic from Code.with_diagnostics when a defp
  # function is referenced only via an MFA tuple in :timer.apply_after/4
  # or :timer.apply_interval/4.
  @real_diag %{
    message: "function do_cleanup/1 is unused",
    position: {7, 3},
    severity: :warning
  }

  test "matches the diagnostic" do
    assert NoPrivateFnInTimerMfa.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unused variable x", position: {1, 1}}
    refute NoPrivateFnInTimerMfa.match?(diag)
  end

  test "does not match non-warning severity" do
    diag = %{severity: :error, message: "function do_cleanup/1 is unused", position: {7, 3}}
    refute NoPrivateFnInTimerMfa.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoPrivateFnInTimerMfa.to_issue(@real_diag).rule ==
             :no_private_fn_in_timer_mfa
  end

  test "preserves the diagnostic message in the issue" do
    assert NoPrivateFnInTimerMfa.to_issue(@real_diag).message ==
             "function do_cleanup/1 is unused"
  end

  test "sets the line in issue meta" do
    assert NoPrivateFnInTimerMfa.to_issue(@real_diag).meta.line == 7
  end
end
