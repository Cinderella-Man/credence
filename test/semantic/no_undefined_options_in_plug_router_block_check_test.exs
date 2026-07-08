defmodule Credence.Semantic.NoUndefinedOptionsInPlugRouterBlockCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUndefinedOptionsInPlugRouterBlock

  @real_message "undefined variable \"options\""

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {177, 25}}
    assert NoUndefinedOptionsInPlugRouterBlock.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoUndefinedOptionsInPlugRouterBlock.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile file (errors have been logged)",
      position: 0
    }

    refute NoUndefinedOptionsInPlugRouterBlock.match?(diag)
  end

  test "ignores undefined variable for other names" do
    diag = %{severity: :error, message: "undefined variable \"foo\"", position: {1, 1}}
    refute NoUndefinedOptionsInPlugRouterBlock.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {177, 25}}

    assert NoUndefinedOptionsInPlugRouterBlock.to_issue(diag).rule ==
             :no_undefined_options_in_plug_router_block
  end

  test "issue message is the diagnostic message" do
    diag = %{severity: :error, message: @real_message, position: {177, 25}}
    assert NoUndefinedOptionsInPlugRouterBlock.to_issue(diag).message == @real_message
  end

  test "issue meta contains the line" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoUndefinedOptionsInPlugRouterBlock.to_issue(diag).meta.line == 42
  end
end
