defmodule Credence.Semantic.FixNegatedCaptureWithArityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixNegatedCaptureWithArity

  @match_message "invalid args for &, expected one of:\n\n  * &Mod.fun/arity to capture a remote function, such as &Enum.map/2\n  * &fun/arity to capture a local or imported function, such as &is_atom/1\n  * &some_code(&1, ...) containing at least one argument as &1, such as &List.flatten(&1)\n\nGot: !Enum.empty?() / 1"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @match_message, position: {3, 35}}
    assert FixNegatedCaptureWithArity.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixNegatedCaptureWithArity.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @match_message, position: {3, 35}}
    assert FixNegatedCaptureWithArity.to_issue(diag).rule == :fix_negated_capture_with_arity
  end
end
