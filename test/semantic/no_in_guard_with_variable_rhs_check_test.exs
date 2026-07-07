defmodule Credence.Semantic.NoInGuardWithVariableRhsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoInGuardWithVariableRhs

  @real_message "invalid right argument for operator \"in\", it expects a compile-time proper list or compile-time range on the right side when used in guard expressions, got: rest"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {4, 22}}
    assert NoInGuardWithVariableRhs.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoInGuardWithVariableRhs.match?(diag)
  end

  test "ignores module redefinition warning" do
    diag = %{
      severity: :warning,
      message:
        "redefining module MarkdownTables (current version loaded from _build/test/lib/workspace/ebin/Elixir.MarkdownTables.beam)",
      position: 1
    }

    refute NoInGuardWithVariableRhs.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {4, 22}}
    assert NoInGuardWithVariableRhs.to_issue(diag).rule == :no_in_guard_with_variable_rhs
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoInGuardWithVariableRhs.to_issue(diag).meta.line == 42
  end
end
