defmodule Credence.Semantic.NoGenserverReplyInHandleCastCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoGenserverReplyInHandleCast

  @real_message "GenServer.reply/2 called inside handle_cast/2 — use send/2 instead"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {19, 9}}
    assert NoGenserverReplyInHandleCast.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoGenserverReplyInHandleCast.match?(diag)
  end

  test "ignores errors" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute NoGenserverReplyInHandleCast.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {19, 9}}
    assert NoGenserverReplyInHandleCast.to_issue(diag).rule == :no_genserver_reply_in_handle_cast
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoGenserverReplyInHandleCast.to_issue(diag).meta.line == 42
  end
end
