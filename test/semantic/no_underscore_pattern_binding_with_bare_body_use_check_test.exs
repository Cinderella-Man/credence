defmodule Credence.Semantic.NoUnderscorePatternBindingWithBareBodyUseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUnderscorePatternBindingWithBareBodyUse

  @real_message "variable \"_old_name\" is unused"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {4, 24}}
    assert NoUnderscorePatternBindingWithBareBodyUse.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUnderscorePatternBindingWithBareBodyUse.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {4, 24}}
    refute NoUnderscorePatternBindingWithBareBodyUse.match?(diag)
  end

  test "ignores non-underscore unused variable" do
    diag = %{severity: :warning, message: "variable \"name\" is unused", position: {1, 1}}
    refute NoUnderscorePatternBindingWithBareBodyUse.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {4, 24}}

    assert NoUnderscorePatternBindingWithBareBodyUse.to_issue(diag).rule ==
             :no_underscore_pattern_binding_with_bare_body_use
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {10, 24}}
    assert NoUnderscorePatternBindingWithBareBodyUse.to_issue(diag).meta.line == 10
  end
end
