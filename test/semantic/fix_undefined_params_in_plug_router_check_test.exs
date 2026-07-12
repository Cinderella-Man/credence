defmodule Credence.Semantic.FixUndefinedParamsInPlugRouterCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUndefinedParamsInPlugRouter

  @real_message "undefined variable \"params\""

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {8, 16}}
    assert FixUndefinedParamsInPlugRouter.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixUndefinedParamsInPlugRouter.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile file (errors have been logged)",
      position: 0
    }

    refute FixUndefinedParamsInPlugRouter.match?(diag)
  end

  test "ignores undefined variable for other names" do
    diag = %{severity: :error, message: "undefined variable \"options\"", position: {1, 1}}
    refute FixUndefinedParamsInPlugRouter.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {8, 16}}

    assert FixUndefinedParamsInPlugRouter.to_issue(diag).rule ==
             :fix_undefined_params_in_plug_router
  end

  test "issue message is the diagnostic message" do
    diag = %{severity: :error, message: @real_message, position: {8, 16}}
    assert FixUndefinedParamsInPlugRouter.to_issue(diag).message == @real_message
  end

  test "issue meta contains the line" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert FixUndefinedParamsInPlugRouter.to_issue(diag).meta.line == 42
  end
end
