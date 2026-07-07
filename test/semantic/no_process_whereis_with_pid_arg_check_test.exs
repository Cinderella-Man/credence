defmodule Credence.Semantic.NoProcessWhereisWithPidArgCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoProcessWhereisWithPidArg

  @real_message "credence_check.ex: cannot compile module EventBus (errors have been logged)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: 0, file: "credence_check.ex"}
    assert NoProcessWhereisWithPidArg.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoProcessWhereisWithPidArg.match?(diag)
  end

  test "ignores specific compile error that is not the generic wrapper" do
    diag = %{
      severity: :error,
      message: "imported Kernel.to_string/1 conflicts with local function",
      position: {2, 8}
    }

    refute NoProcessWhereisWithPidArg.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: 0, file: "credence_check.ex"}
    assert NoProcessWhereisWithPidArg.to_issue(diag).rule == :no_process_whereis_with_pid_arg
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {5, 1}, file: "credence_check.ex"}
    assert NoProcessWhereisWithPidArg.to_issue(diag).meta.line == 5
  end
end
