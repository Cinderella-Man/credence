defmodule Credence.Semantic.NoUnusedTypeDeclarationCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUnusedTypeDeclaration

  @real_diag %{message: "type step/0 is unused", position: 11, severity: :warning}

  test "matches the diagnostic" do
    assert NoUnusedTypeDeclaration.match?(@real_diag)
  end

  test "matches with different type names and arities" do
    diag = %{severity: :warning, message: "type my_type/1 is unused", position: {5, 3}}
    assert NoUnusedTypeDeclaration.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUnusedTypeDeclaration.match?(diag)
  end

  test "ignores non-warning diagnostics" do
    diag = %{severity: :error, message: "type step/0 is unused", position: {3, 3}}
    refute NoUnusedTypeDeclaration.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoUnusedTypeDeclaration.to_issue(@real_diag).rule == :no_unused_type_declaration
  end

  test "sets the line in issue meta from integer position" do
    assert NoUnusedTypeDeclaration.to_issue(@real_diag).meta.line == 11
  end

  test "sets the line in issue meta from tuple position" do
    diag = %{severity: :warning, message: "type step/0 is unused", position: {7, 5}}
    assert NoUnusedTypeDeclaration.to_issue(diag).meta.line == 7
  end
end
