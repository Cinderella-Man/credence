defmodule Credence.Semantic.NoDateUtcTodayWithArgCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDateUtcTodayWithArg

  @real_message "this clause for process_file/2 cannot match because a previous clause at line 30 always matches"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {34, 8}, file: "credence_check.ex"}
    assert NoDateUtcTodayWithArg.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoDateUtcTodayWithArg.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile module (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoDateUtcTodayWithArg.match?(diag)
  end

  test "ignores the no_unreachable_function_clause message" do
    diag = %{
      severity: :warning,
      message: "this clause cannot match because a previous clause at line 5 matches the same pattern as this clause",
      position: {10, 3}
    }

    refute NoDateUtcTodayWithArg.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {34, 8}, file: "credence_check.ex"}
    assert NoDateUtcTodayWithArg.to_issue(diag).rule == :no_date_utc_today_with_arg
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}, file: "credence_check.ex"}
    assert NoDateUtcTodayWithArg.to_issue(diag).meta.line == 42
  end
end
