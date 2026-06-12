defmodule Credence.Semantic.NoNonNegatedIntegerCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoNonNegatedInteger

  @diagnostic %{
    message:
      "credence_check.ex:5: type non_negated_integer/0 undefined (no such type in Solution)",
    position: 5,
    file: "credence_check.ex",
    severity: :error
  }

  test "matches the diagnostic" do
    assert NoNonNegatedInteger.match?(@diagnostic)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoNonNegatedInteger.match?(diag)
  end

  test "ignores warnings" do
    diag = %{severity: :warning, message: "type non_negated_integer/0 undefined", position: {1, 1}}
    refute NoNonNegatedInteger.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoNonNegatedInteger.to_issue(@diagnostic).rule == :no_non_negated_integer
  end

  test "preserves the diagnostic message" do
    assert NoNonNegatedInteger.to_issue(@diagnostic).message == @diagnostic.message
  end

  test "extracts line from integer position" do
    issue = NoNonNegatedInteger.to_issue(@diagnostic)
    assert issue.meta.line == 5
  end

  test "extracts line from tuple position" do
    diag = %{severity: :error, message: "type non_negated_integer/0 undefined", position: {3, 7}}
    issue = NoNonNegatedInteger.to_issue(diag)
    assert issue.meta.line == 3
  end
end
