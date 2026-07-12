defmodule Credence.Semantic.FixApplyOnFunctionReferenceCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixApplyOnFunctionReference

  @match_msg "apply(:call, []) detected — use receiver.() instead"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @match_msg, position: {3, 5}}
    assert FixApplyOnFunctionReference.match?(diag)
  end

  test "matches error severity" do
    diag = %{severity: :error, message: @match_msg, position: {3, 5}}
    assert FixApplyOnFunctionReference.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixApplyOnFunctionReference.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_msg, position: {3, 5}}
    assert FixApplyOnFunctionReference.to_issue(diag).rule == :fix_apply_on_function_reference
  end

  test "captures the line from the diagnostic" do
    diag = %{severity: :warning, message: @match_msg, position: {3, 5}}
    assert FixApplyOnFunctionReference.to_issue(diag).meta.line == 3
  end
end
