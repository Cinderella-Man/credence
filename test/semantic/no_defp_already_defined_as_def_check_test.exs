defmodule Credence.Semantic.NoDefpAlreadyDefinedAsDefCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDefpAlreadyDefinedAsDef

  @real_message "defp sequence/2 already defined as def"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {8, 3}}
    assert NoDefpAlreadyDefinedAsDef.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoDefpAlreadyDefinedAsDef.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile file (errors have been logged)",
      position: 0
    }

    refute NoDefpAlreadyDefinedAsDef.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {8, 3}}

    assert NoDefpAlreadyDefinedAsDef.to_issue(diag).rule ==
             :no_defp_already_defined_as_def
  end

  test "issue message is the diagnostic message" do
    diag = %{severity: :error, message: @real_message, position: {8, 3}}
    assert NoDefpAlreadyDefinedAsDef.to_issue(diag).message == @real_message
  end

  test "issue meta contains the line" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoDefpAlreadyDefinedAsDef.to_issue(diag).meta.line == 42
  end
end
