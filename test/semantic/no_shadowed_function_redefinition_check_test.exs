defmodule Credence.Semantic.NoShadowedFunctionRedefinitionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoShadowedFunctionRedefinition

  @real_message "this clause cannot match because a previous clause at line 2 always matches"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {8, 3}}
    assert NoShadowedFunctionRedefinition.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoShadowedFunctionRedefinition.match?(diag)
  end

  test "ignores the same-pattern variant handled by NoUnreachableFunctionClause" do
    diag = %{
      severity: :warning,
      message:
        "this clause cannot match because a previous clause at line 5 matches the same pattern as this clause",
      position: {6, 8}
    }

    refute NoShadowedFunctionRedefinition.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {8, 3}}
    assert NoShadowedFunctionRedefinition.to_issue(diag).rule == :no_shadowed_function_redefinition
  end

  test "issue message is the diagnostic message" do
    diag = %{severity: :warning, message: @real_message, position: {8, 3}}
    assert NoShadowedFunctionRedefinition.to_issue(diag).message == @real_message
  end

  test "issue meta contains the line" do
    diag = %{severity: :warning, message: @real_message, position: {8, 3}}
    assert NoShadowedFunctionRedefinition.to_issue(diag).meta.line == 8
  end
end
