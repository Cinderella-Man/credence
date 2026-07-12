defmodule Credence.Semantic.NoProcessSendTwoArgsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoProcessSendTwoArgs

  @real_message "expected a map or struct when accessing .normal in expression:\n\n    new_queue.normal\n\nwhere \"new_queue\" was given the type:\n\n    # type: empty_list()\n    # from: credence_check.ex:143:7\n    {nil, new_queue, state}\n\nhint: \"var.field\" (without parentheses) means \"var\" is a map() while \"var.fun()\" (with parentheses) means \"var\" is an atom()\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {145, 39}}
    assert NoProcessSendTwoArgs.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoProcessSendTwoArgs.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {145, 39}}
    assert NoProcessSendTwoArgs.to_issue(diag).rule == :no_process_send_two_args
  end
end
