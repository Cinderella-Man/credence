defmodule Credence.Semantic.NoRedefineBuiltinTypeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoRedefineBuiltinType

  @real_message "credence_check.ex:2: type node/0 is a built-in type and it cannot be redefined"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {2, 1}}
    assert NoRedefineBuiltinType.match?(diag)
  end

  test "matches for different type names" do
    diag = %{
      severity: :error,
      message: "file.ex:1: type atom/0 is a built-in type and it cannot be redefined",
      position: {1, 1}
    }

    assert NoRedefineBuiltinType.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoRedefineBuiltinType.match?(diag)
  end

  test "ignores warning severity" do
    diag = %{severity: :warning, message: @real_message, position: {2, 1}}
    refute NoRedefineBuiltinType.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {2, 1}}
    assert NoRedefineBuiltinType.to_issue(diag).rule == :no_redefine_builtin_type
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoRedefineBuiltinType.to_issue(diag).meta.line == 42
  end

  test "sets the line from integer position" do
    diag = %{severity: :error, message: @real_message, position: 7}
    assert NoRedefineBuiltinType.to_issue(diag).meta.line == 7
  end
end
