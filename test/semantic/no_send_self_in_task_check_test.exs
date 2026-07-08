defmodule Credence.Semantic.NoSendSelfInTaskCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoSendSelfInTask

  @real_message "send(self(), ...) called inside a Task callback; self() refers to the task process, not the parent"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {21, 7}}
    assert NoSendSelfInTask.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated warning", position: {1, 1}}
    refute NoSendSelfInTask.match?(diag)
  end

  test "ignores errors" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute NoSendSelfInTask.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {21, 7}}
    assert NoSendSelfInTask.to_issue(diag).rule == :no_send_self_in_task
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoSendSelfInTask.to_issue(diag).meta.line == 42
  end
end
