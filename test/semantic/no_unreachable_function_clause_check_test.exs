defmodule Credence.Semantic.NoUnreachableFunctionClauseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUnreachableFunctionClause

  @real_message "this clause cannot match because a previous clause at line 5 matches the same pattern as this clause"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {6, 8}}
    assert NoUnreachableFunctionClause.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUnreachableFunctionClause.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {6, 8}}
    assert NoUnreachableFunctionClause.to_issue(diag).rule == :no_unreachable_function_clause
  end

  test "issue message is the diagnostic message" do
    diag = %{severity: :warning, message: @real_message, position: {6, 8}}
    assert NoUnreachableFunctionClause.to_issue(diag).message == @real_message
  end

  test "issue meta contains the line" do
    diag = %{severity: :warning, message: @real_message, position: {6, 8}}
    assert NoUnreachableFunctionClause.to_issue(diag).meta.line == 6
  end
end
