defmodule Credence.Semantic.FixMapFetchNoneClauseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixMapFetchNoneClause

  @real_message "an expression is always required on the right side of ->. Please provide a value after ->"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {258, 33}}
    assert FixMapFetchNoneClause.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixMapFetchNoneClause.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {258, 33}}
    assert FixMapFetchNoneClause.to_issue(diag).rule == :fix_map_fetch_none_clause
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 5}}
    assert FixMapFetchNoneClause.to_issue(diag).meta.line == 42
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute FixMapFetchNoneClause.match?(diag)
  end
end
