defmodule Credence.Semantic.FixApplyArityOneCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixApplyArityOne

  @match_msg "undefined function apply/1 (expected X to define such a function or for it to be imported, but none are available)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @match_msg, position: {2, 17}}
    assert FixApplyArityOne.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixApplyArityOne.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @match_msg, position: {2, 17}}
    assert FixApplyArityOne.to_issue(diag).rule == :fix_apply_arity_one
  end
end
