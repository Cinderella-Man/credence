defmodule Credence.Semantic.NoRescueInCondCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoRescueInCond

  @real_message_rescue "unexpected option :rescue in \"cond\""
  @real_message_catch "unexpected option :catch in \"cond\""

  test "matches the :rescue diagnostic" do
    diag = %{severity: :error, message: @real_message_rescue, position: {3, 5}}
    assert NoRescueInCond.match?(diag)
  end

  test "matches the :catch diagnostic" do
    diag = %{severity: :error, message: @real_message_catch, position: {3, 5}}
    assert NoRescueInCond.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoRescueInCond.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile module Foo (errors have been logged)",
      position: 0
    }

    refute NoRescueInCond.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message_rescue, position: {3, 5}}
    assert NoRescueInCond.to_issue(diag).rule == :no_rescue_in_cond
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message_rescue, position: {42, 5}}
    assert NoRescueInCond.to_issue(diag).meta.line == 42
  end
end
