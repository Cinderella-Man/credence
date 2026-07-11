defmodule Credence.Semantic.NoUnreachableDuplicateFunctionClauseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUnreachableDuplicateFunctionClause

  @real_diag %{
    message: "no match of right hand side value:\n\n    [:notifications_server, :timeout_ms]\n",
    position: 0,
    file: "credence_check.ex",
    severity: :error
  }

  test "matches the diagnostic" do
    assert NoUnreachableDuplicateFunctionClause.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUnreachableDuplicateFunctionClause.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoUnreachableDuplicateFunctionClause.to_issue(@real_diag).rule ==
             :no_unreachable_duplicate_function_clause
  end
end
