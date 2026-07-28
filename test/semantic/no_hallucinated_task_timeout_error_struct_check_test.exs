defmodule Credence.Semantic.NoHallucinatedTaskTimeoutErrorStructCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedTaskTimeoutErrorStruct

  @real_message "Task.TimeoutError.__struct__/1 is undefined, cannot expand struct Task.TimeoutError. Make sure the struct name is correct. If the struct name exists and is correct but it still cannot be found, you likely have cyclic module usage in your code"

  test "matches the diagnostic" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {12, 7},
      file: "credence_check.ex"
    }

    assert NoHallucinatedTaskTimeoutErrorStruct.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{
      severity: :error,
      message: "unrelated error",
      position: {1, 1},
      file: "credence_check.ex"
    }

    refute NoHallucinatedTaskTimeoutErrorStruct.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Factory (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedTaskTimeoutErrorStruct.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {12, 7},
      file: "credence_check.ex"
    }

    assert NoHallucinatedTaskTimeoutErrorStruct.to_issue(diag).rule ==
             :no_hallucinated_task_timeout_error_struct
  end

  test "sets the line in issue meta" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {42, 5},
      file: "credence_check.ex"
    }

    assert NoHallucinatedTaskTimeoutErrorStruct.to_issue(diag).meta.line == 42
  end

  test "ignores warning severity" do
    diag = %{
      severity: :warning,
      message: @real_message,
      position: {12, 7},
      file: "credence_check.ex"
    }

    refute NoHallucinatedTaskTimeoutErrorStruct.match?(diag)
  end
end
