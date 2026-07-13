defmodule Credence.Semantic.FixPinInEtsMatchSpecCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixPinInEtsMatchSpec

  @real_message "misplaced operator ^name\n\nThe pin operator ^ is supported only inside matches or inside custom macros. Make sure you are inside a match or all necessary macros have been required"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {3, 32}}
    assert FixPinInEtsMatchSpec.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixPinInEtsMatchSpec.match?(diag)
  end

  test "ignores warning severity" do
    diag = %{severity: :warning, message: @real_message, position: {3, 32}}
    refute FixPinInEtsMatchSpec.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {3, 32}}
    assert FixPinInEtsMatchSpec.to_issue(diag).rule == :fix_pin_in_ets_match_spec
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 7}}
    assert FixPinInEtsMatchSpec.to_issue(diag).meta.line == 42
  end
end
