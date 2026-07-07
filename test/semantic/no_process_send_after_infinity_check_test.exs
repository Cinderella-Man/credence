defmodule Credence.Semantic.NoProcessSendAfterInfinityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoProcessSendAfterInfinity

  @real_message "redefining module SessionStore (current version loaded from _build/test/lib/workspace/ebin/Elixir.SessionStore.beam)"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {1, 1}}
    assert NoProcessSendAfterInfinity.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoProcessSendAfterInfinity.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {1, 1}}
    assert NoProcessSendAfterInfinity.to_issue(diag).rule == :no_process_send_after_infinity
  end
end
