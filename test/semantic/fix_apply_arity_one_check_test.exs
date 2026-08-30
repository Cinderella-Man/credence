defmodule Credence.Semantic.FixApplyArityOneCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixApplyArityOne

  @match_msg "undefined function apply/1 (expected X to define such a function or for it to be imported, but none are available)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @match_msg, position: {2, 17}}
    assert FixApplyArityOne.match?(diag)
  end

  test "ignores the same message at warning severity" do
    diag = %{severity: :warning, message: @match_msg, position: {2, 17}}
    refute FixApplyArityOne.match?(diag)
  end

  test "ignores other apply arities whose message contains the apply/1 substring" do
    msg =
      "undefined function apply/12 (expected X to define such a function or for it to be imported, but none are available)"

    diag = %{severity: :error, message: msg, position: {2, 17}}
    refute FixApplyArityOne.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixApplyArityOne.match?(diag)
  end

  test "attributes the issue to this rule with the diagnostic line" do
    diag = %{severity: :error, message: @match_msg, position: {2, 17}}
    issue = FixApplyArityOne.to_issue(diag)
    assert issue.rule == :fix_apply_arity_one
    assert issue.meta.line == 2
  end
end
