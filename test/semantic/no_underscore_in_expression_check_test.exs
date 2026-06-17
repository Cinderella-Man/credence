defmodule Credence.Semantic.NoUnderscoreInExpressionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUnderscoreInExpression

  test "ignores redefining module diagnostic" do
    diag = %{
      severity: :warning,
      message:
        "redefining module Solution (current version loaded from _build/test/lib/workspace/ebin/Elixir.Solution.beam)",
      position: 1
    }

    refute NoUnderscoreInExpression.match?(diag)
  end

  test "matches the invalid use of underscore diagnostic" do
    diag = %{
      severity: :error,
      message:
        "invalid use of _. _ can only be used inside patterns to ignore values and cannot be used in expressions. Make sure you are inside a pattern or change it accordingly",
      position: {4, 8}
    }

    assert NoUnderscoreInExpression.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUnderscoreInExpression.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :error,
      message:
        "invalid use of _. _ can only be used inside patterns to ignore values and cannot be used in expressions. Make sure you are inside a pattern or change it accordingly",
      position: {4, 8}
    }

    assert NoUnderscoreInExpression.to_issue(diag).rule == :no_underscore_in_expression
  end
end
