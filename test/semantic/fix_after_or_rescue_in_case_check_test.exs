defmodule Credence.Semantic.FixAfterOrRescueInCaseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixAfterOrRescueInCase

  @real_message_after "unexpected option :after in \"case\""
  @real_message_rescue "unexpected option :rescue in \"case\""

  test "matches the :after diagnostic" do
    diag = %{severity: :error, message: @real_message_after, position: {3, 5}}
    assert FixAfterOrRescueInCase.match?(diag)
  end

  test "matches the :rescue diagnostic" do
    diag = %{severity: :error, message: @real_message_rescue, position: {3, 5}}
    assert FixAfterOrRescueInCase.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixAfterOrRescueInCase.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile module Foo (errors have been logged)",
      position: 0
    }

    refute FixAfterOrRescueInCase.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message_after, position: {3, 5}}
    assert FixAfterOrRescueInCase.to_issue(diag).rule == :fix_after_or_rescue_in_case
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message_after, position: {42, 5}}
    assert FixAfterOrRescueInCase.to_issue(diag).meta.line == 42
  end
end
