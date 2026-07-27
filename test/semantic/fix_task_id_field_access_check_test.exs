defmodule Credence.Semantic.FixTaskIdFieldAccessCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixTaskIdFieldAccess

  @real_message "unknown key .id in expression:\n\n    task.id\n\nthe given type does not have the given key:\n\n    dynamic(%Task{mfa: {term(), term(), integer()}, owner: pid(), pid: term(), ref: term()})\n\nwhere \"task\" was given the type:\n\n    # type: dynamic(%Task{mfa: {term(), term(), integer()}, owner: pid()})\n    # from: credence_check.ex:52:14\n    task =\n      Task.async(fn ->\n        try do\n          func.(item)\n        catch\n          error, reason -> {:error, {error, reason}}\n        else\n          value -> value\n        end\n      end)\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {62, 55}}
    assert FixTaskIdFieldAccess.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixTaskIdFieldAccess.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :warning,
      message: "credence_check.ex: cannot compile module (errors have been logged)",
      position: 0
    }

    refute FixTaskIdFieldAccess.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {62, 55}}
    assert FixTaskIdFieldAccess.to_issue(diag).rule == :fix_task_id_field_access
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 5}}
    assert FixTaskIdFieldAccess.to_issue(diag).meta.line == 42
  end
end
