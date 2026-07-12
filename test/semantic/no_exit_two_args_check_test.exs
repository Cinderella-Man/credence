defmodule Credence.Semantic.NoExitTwoArgsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoExitTwoArgs

  @real_message "undefined function exit/2 (expected TimeoutWorker to define such a function or for it to be imported, but none are available)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {6, 10}}
    assert NoExitTwoArgs.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoExitTwoArgs.match?(diag)
  end

  test "ignores undefined function for other functions" do
    diag = %{severity: :error, message: "undefined function foo/2", position: {1, 1}}
    refute NoExitTwoArgs.match?(diag)
  end

  test "ignores undefined function exit/1 (Kernel.exit exists)" do
    diag = %{severity: :error, message: "undefined function exit/1", position: {1, 1}}
    refute NoExitTwoArgs.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {6, 10}}
    assert NoExitTwoArgs.to_issue(diag).rule == :no_exit_two_args
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoExitTwoArgs.to_issue(diag).meta.line == 42
  end
end
