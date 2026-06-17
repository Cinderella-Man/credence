defmodule Credence.Semantic.RemoveUnusedTypespecWhenVarCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.RemoveUnusedTypespecWhenVar

  @message "credence_check.ex:2: type variable var_ok is used only once. Type variables in typespecs must be referenced at least twice, otherwise it is equivalent to term()"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @message, position: 2, file: "credence_check.ex"}
    assert RemoveUnusedTypespecWhenVar.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute RemoveUnusedTypespecWhenVar.match?(diag)
  end

  test "ignores non-binary message" do
    refute RemoveUnusedTypespecWhenVar.match?(%{message: nil})
    refute RemoveUnusedTypespecWhenVar.match?(%{})
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @message, position: 2, file: "credence_check.ex"}
    assert RemoveUnusedTypespecWhenVar.to_issue(diag).rule == :remove_unused_typespec_when_var
  end

  test "records the diagnostic line in the issue" do
    diag = %{severity: :error, message: @message, position: 2, file: "credence_check.ex"}
    assert RemoveUnusedTypespecWhenVar.to_issue(diag).meta.line == 2
  end
end
