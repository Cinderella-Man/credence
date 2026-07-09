defmodule Credence.Semantic.NoRescueInWithExpressionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoRescueInWithExpression

  @rescue_diag %{
    severity: :error,
    message: "unexpected option :rescue in \"with\"",
    position: {75, 5}
  }

  @catch_diag %{
    severity: :error,
    message: "unexpected option :catch in \"with\"",
    position: {75, 5}
  }

  test "matches the :rescue diagnostic" do
    assert NoRescueInWithExpression.match?(@rescue_diag)
  end

  test "matches the :catch diagnostic" do
    assert NoRescueInWithExpression.match?(@catch_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoRescueInWithExpression.match?(diag)
  end

  test "ignores rescue in case (handled by another rule)" do
    diag = %{severity: :error, message: ~S(unexpected option :rescue in "case"), position: {1, 1}}
    refute NoRescueInWithExpression.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoRescueInWithExpression.to_issue(@rescue_diag).rule == :no_rescue_in_with_expression
  end

  test "preserves the diagnostic message" do
    assert NoRescueInWithExpression.to_issue(@rescue_diag).message ==
             "unexpected option :rescue in \"with\""
  end
end
