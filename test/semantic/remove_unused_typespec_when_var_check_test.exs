defmodule Credence.Semantic.RemoveUnusedTypespecWhenVarCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.RemoveUnusedTypespecWhenVar

  test "matches the diagnostic" do
    diag = %{severity: :error, message: "credence_check.ex:19: type variable var_ok is used only once. Type variables in typespecs must be referenced at least twice, otherwise it is equivalent to term()", position: 19, file: "credence_check.ex"}
    assert RemoveUnusedTypespecWhenVar.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute RemoveUnusedTypespecWhenVar.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: "credence_check.ex:19: type variable var_ok is used only once. Type variables in typespecs must be referenced at least twice, otherwise it is equivalent to term()", position: 19, file: "credence_check.ex"}
    assert RemoveUnusedTypespecWhenVar.to_issue(diag).rule == :remove_unused_typespec_when_var
  end
end
