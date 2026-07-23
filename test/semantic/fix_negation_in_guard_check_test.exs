defmodule Credence.Semantic.FixNegationInGuardCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixNegationInGuard

  @real_message "invalid expression in guard, ! is not allowed in guards. To learn more about guards, visit: https://hexdocs.pm/elixir/patterns-and-guards.html"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {2, 42}, file: "credence_check.ex"}
    assert FixNegationInGuard.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute FixNegationInGuard.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixNegationInGuard.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {2, 42}, file: "credence_check.ex"}
    assert FixNegationInGuard.to_issue(diag).rule == :fix_negation_in_guard
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}, file: "credence_check.ex"}
    assert FixNegationInGuard.to_issue(diag).meta.line == 42
  end
end
