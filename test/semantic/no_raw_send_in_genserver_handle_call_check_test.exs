defmodule Credence.Semantic.NoRawSendInGenserverHandleCallCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoRawSendInGenserverHandleCall

  @real_message "send/2 spawned from handle_call/3 — use GenServer.reply/2 instead"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {22, 7}}
    assert NoRawSendInGenserverHandleCall.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoRawSendInGenserverHandleCall.match?(diag)
  end

  test "ignores errors" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute NoRawSendInGenserverHandleCall.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {22, 7}}

    assert NoRawSendInGenserverHandleCall.to_issue(diag).rule ==
             :no_raw_send_in_genserver_handle_call
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoRawSendInGenserverHandleCall.to_issue(diag).meta.line == 42
  end
end
