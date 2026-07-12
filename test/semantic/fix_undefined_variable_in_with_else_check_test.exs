defmodule Credence.Semantic.FixUndefinedVariableInWithElseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUndefinedVariableInWithElse

  test "matches the diagnostic" do
    diag = %{severity: :error, message: ~s(undefined variable "sigs"), position: {3, 5}}
    assert FixUndefinedVariableInWithElse.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixUndefinedVariableInWithElse.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: ~s(undefined variable "sigs"), position: {3, 5}}

    assert FixUndefinedVariableInWithElse.to_issue(diag).rule ==
             :fix_undefined_variable_in_with_else
  end
end
