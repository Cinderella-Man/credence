defmodule Credence.Semantic.NoOrInCasePatternCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoOrInCasePattern

  # The exact message the compiler raises for `nil or "" ->` in a case clause.
  @real_message "invalid expression in match, or is not allowed in patterns such as " <>
                  "function clauses, case clauses or on the left side of the = operator"

  test "matches the real compiler diagnostic" do
    diag = %{severity: :error, message: @real_message, position: 0}
    assert NoOrInCasePattern.match?(diag)
  end

  test "ignores warning-severity diagnostics with the same text" do
    diag = %{severity: :warning, message: @real_message, position: 0}
    refute NoOrInCasePattern.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoOrInCasePattern.match?(diag)
  end

  test "ignores the generic compile-error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile module Foo (errors have been logged)",
      position: 0
    }

    refute NoOrInCasePattern.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {42, 1}}
    assert NoOrInCasePattern.to_issue(diag).rule == :no_or_in_case_pattern
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 1}}
    assert NoOrInCasePattern.to_issue(diag).meta.line == 42
  end
end
