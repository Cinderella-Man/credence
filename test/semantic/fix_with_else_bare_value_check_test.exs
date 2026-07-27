defmodule Credence.Semantic.FixWithElseBareValueCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixWithElseBareValue

  @real_message ~s(expected -> clauses for :else in "with")

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {59, 5}}
    assert FixWithElseBareValue.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixWithElseBareValue.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile module Foo (errors have been logged)",
      position: 0
    }

    refute FixWithElseBareValue.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {59, 5}}
    assert FixWithElseBareValue.to_issue(diag).rule == :fix_with_else_bare_value
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}}
    assert FixWithElseBareValue.to_issue(diag).meta.line == 42
  end
end
