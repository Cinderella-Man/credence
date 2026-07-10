defmodule Credence.Semantic.FixRegexInGuardCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixRegexInGuard

  @real_message "escaped Regex structs are not allowed in match or guards"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {2, 42}, file: "credence_check.ex"}
    assert FixRegexInGuard.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute FixRegexInGuard.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixRegexInGuard.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {2, 42}, file: "credence_check.ex"}
    assert FixRegexInGuard.to_issue(diag).rule == :fix_regex_in_guard
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}, file: "credence_check.ex"}
    assert FixRegexInGuard.to_issue(diag).meta.line == 42
  end
end
