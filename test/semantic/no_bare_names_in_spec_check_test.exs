defmodule Credence.Semantic.NoBareNamesInSpecCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoBareNamesInSpec

  @diagnostic %{
    message: "credence_check.ex:6: type sub_list/0 undefined (no such type in Solution)",
    position: 6,
    file: "credence_check.ex",
    severity: :error
  }

  test "matches the diagnostic" do
    assert NoBareNamesInSpec.match?(@diagnostic)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoBareNamesInSpec.match?(diag)
  end

  test "ignores warnings" do
    diag = %{severity: :warning, message: "type sub_list/0 undefined", position: {1, 1}}
    refute NoBareNamesInSpec.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoBareNamesInSpec.to_issue(@diagnostic).rule == :no_bare_names_in_spec
  end

  test "preserves the diagnostic message" do
    assert NoBareNamesInSpec.to_issue(@diagnostic).message == @diagnostic.message
  end

  test "extracts line from integer position" do
    issue = NoBareNamesInSpec.to_issue(@diagnostic)
    assert issue.meta.line == 6
  end

  test "extracts line from tuple position" do
    diag = %{severity: :error, message: "type x/0 undefined", position: {3, 7}}
    issue = NoBareNamesInSpec.to_issue(diag)
    assert issue.meta.line == 3
  end
end
