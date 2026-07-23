defmodule Credence.Semantic.NoRescueInWithExpressionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoRescueInWithExpression

  @message_rescue ~S(unexpected option :rescue in "with")
  @message_catch ~S(unexpected option :catch in "with")

  test "matches the :rescue diagnostic" do
    diag = %{severity: :error, message: @message_rescue, position: {3, 5}}
    assert NoRescueInWithExpression.match?(diag)
  end

  test "matches the :catch diagnostic" do
    diag = %{severity: :error, message: @message_catch, position: {3, 5}}
    assert NoRescueInWithExpression.match?(diag)
  end

  test "ignores the :after-in-with diagnostic (the fix only claims rescue/catch)" do
    diag = %{severity: :error, message: ~S(unexpected option :after in "with"), position: {3, 5}}
    refute NoRescueInWithExpression.match?(diag)
  end

  test "ignores the cond variant, which another rule owns" do
    diag = %{severity: :error, message: ~S(unexpected option :rescue in "cond"), position: {1, 1}}
    refute NoRescueInWithExpression.match?(diag)
  end

  test "ignores the case variant, which another rule owns" do
    diag = %{severity: :error, message: ~S(unexpected option :rescue in "case"), position: {1, 1}}
    refute NoRescueInWithExpression.match?(diag)
  end

  test "ignores warning-severity diagnostics" do
    diag = %{severity: :warning, message: @message_rescue, position: {3, 5}}
    refute NoRescueInWithExpression.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoRescueInWithExpression.match?(diag)
  end

  test "ignores a diagnostic with a non-binary message" do
    refute NoRescueInWithExpression.match?(%{severity: :error, message: nil, position: {1, 1}})
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @message_rescue, position: {75, 5}}
    assert NoRescueInWithExpression.to_issue(diag).rule == :no_rescue_in_with_expression
  end

  test "preserves the diagnostic message and line" do
    diag = %{severity: :error, message: @message_rescue, position: {75, 5}}
    issue = NoRescueInWithExpression.to_issue(diag)

    assert issue.message == @message_rescue
    assert issue.meta == %{line: 75}
  end

  test "accepts an integer position" do
    diag = %{severity: :error, message: @message_catch, position: 12}
    assert NoRescueInWithExpression.to_issue(diag).meta == %{line: 12}
  end

  # The claimed strings are the compiler's verbatim wording — confirmed against
  # `Code.with_diagnostics/1` on a `with … rescue … end` fixture, which emits
  # `%{severity: :error, message: ~S(unexpected option :rescue in "with"),
  # position: {3, 5}}`. Rule tests may not reach for the parser themselves, so
  # the shape is pinned here as the fixtures above rather than re-compiled.
  test "matches the real diagnostic shape the compiler emits" do
    diag = %{
      message: @message_rescue,
      position: {3, 5},
      file: "nofile",
      source: "nofile",
      span: nil,
      severity: :error
    }

    assert NoRescueInWithExpression.match?(diag)
    assert NoRescueInWithExpression.to_issue(diag).meta == %{line: 3}
  end
end
