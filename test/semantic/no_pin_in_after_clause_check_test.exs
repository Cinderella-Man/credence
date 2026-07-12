defmodule Credence.Semantic.NoPinInAfterClauseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoPinInAfterClause

  @real_message "misplaced operator ^timeout_ms\n\nThe pin operator ^ is supported only inside matches or inside custom macros. Make sure you are inside a match or all necessary macros have been required"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {7, 7}}
    assert NoPinInAfterClause.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoPinInAfterClause.match?(diag)
  end

  test "ignores warning severity" do
    diag = %{severity: :warning, message: @real_message, position: {7, 7}}
    refute NoPinInAfterClause.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {7, 7}}
    assert NoPinInAfterClause.to_issue(diag).rule == :no_pin_in_after_clause
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 7}}
    assert NoPinInAfterClause.to_issue(diag).meta.line == 42
  end
end
