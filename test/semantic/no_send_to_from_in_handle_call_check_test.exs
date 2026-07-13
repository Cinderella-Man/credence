defmodule Credence.Semantic.NoSendToFromInHandleCallCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoSendToFromInHandleCall

  @real_message "send/2 called with handle_call from — use GenServer.reply/2 instead"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {18, 7}}
    assert NoSendToFromInHandleCall.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoSendToFromInHandleCall.match?(diag)
  end

  test "ignores errors" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute NoSendToFromInHandleCall.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {18, 7}}
    assert NoSendToFromInHandleCall.to_issue(diag).rule == :no_send_to_from_in_handle_call
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoSendToFromInHandleCall.to_issue(diag).meta.line == 42
  end
end
