defmodule Credence.Semantic.FixTaskRefFieldAccessCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixTaskRefFieldAccess

  # Real diagnostic shape from `Code.with_diagnostics/1` compiling
  #
  #     defmodule DemoX do
  #       def go(t), do: Task.ref(t)
  #     end
  #
  # — the column points at `ref`.
  @message "Task.ref/1 is undefined or private"
  @diag %{severity: :warning, message: @message, position: {2, 23}}

  test "matches the Task.ref/1 diagnostic" do
    assert FixTaskRefFieldAccess.match?(@diag)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(@diag))

    assert winner == FixTaskRefFieldAccess
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "ignores other arities (Task.ref/2 has no field-access equivalent)" do
    diag = %{
      severity: :warning,
      message: "Task.ref/2 is undefined or private",
      position: {2, 23}
    }

    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "ignores a double-digit arity that shares the /1 prefix" do
    diag = %{
      severity: :warning,
      message: "Task.ref/12 is undefined or private",
      position: {2, 23}
    }

    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "ignores a user module whose path merely ends in Task" do
    diag = %{
      severity: :warning,
      message: "MyApp.Task.ref/1 is undefined or private",
      position: {2, 23}
    }

    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "ignores the unavailable-module wording for a missing module" do
    diag = %{
      severity: :warning,
      message:
        "MyTask.ref/1 is undefined (module MyTask is not available or is yet to be defined)",
      position: {2, 23}
    }

    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "ignores error-severity diagnostics" do
    diag = %{severity: :error, message: @message, position: {2, 23}}
    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "ignores the module-shadowing error (a different diagnostic this rule must not claim)" do
    diag = %{
      severity: :error,
      message:
        "you are trying to use/import/require the module RetryDedup.Application which is currently being defined.",
      position: 3
    }

    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixTaskRefFieldAccess.to_issue(@diag).rule == :fix_task_ref_field_access
  end

  test "issue preserves the diagnostic message" do
    assert FixTaskRefFieldAccess.to_issue(@diag).message == @message
  end

  test "sets the line in issue meta from a tuple position" do
    diag = %{severity: :warning, message: @message, position: {42, 10}}
    assert FixTaskRefFieldAccess.to_issue(diag).meta.line == 42
  end

  test "sets the line in issue meta from an integer position" do
    diag = %{severity: :warning, message: @message, position: 7}
    assert FixTaskRefFieldAccess.to_issue(diag).meta.line == 7
  end
end
