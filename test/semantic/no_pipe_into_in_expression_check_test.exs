defmodule Credence.Semantic.NoPipeIntoInExpressionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoPipeIntoInExpression

  @real_diag %{
    severity: :error,
    message:
      "cannot pipe to_string(key) into String.downcase() in masker.sensitive_key_set, the :in operator can only take two arguments",
    position: 0
  }

  test "matches the diagnostic" do
    assert NoPipeIntoInExpression.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoPipeIntoInExpression.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoPipeIntoInExpression.to_issue(@real_diag).rule == :no_pipe_into_in_expression
  end

  test "preserves the original message in the issue" do
    assert NoPipeIntoInExpression.to_issue(@real_diag).message == @real_diag.message
  end
end
