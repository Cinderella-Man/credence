defmodule Credence.Semantic.NoReturnFnInConditionalCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoReturnFnInConditional

  @real_message "undefined function return/1 (expected ReturnInUnless to define such a function or for it to be imported, but none are available)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {9, 7}}
    assert NoReturnFnInConditional.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoReturnFnInConditional.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module ReturnInUnless (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoReturnFnInConditional.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {9, 7}}
    assert NoReturnFnInConditional.to_issue(diag).rule == :no_return_fn_in_conditional
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}}
    assert NoReturnFnInConditional.to_issue(diag).meta.line == 42
  end

  test "ignores warning severity" do
    diag = %{severity: :warning, message: @real_message, position: {3, 5}}
    refute NoReturnFnInConditional.match?(diag)
  end
end
