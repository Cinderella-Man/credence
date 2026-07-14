defmodule Credence.Semantic.NoRaiseInHandleCallCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoRaiseInHandleCall

  @real_message "raise in handle_call — use {:reply, {:error, msg}, state} instead"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {17, 5}}
    assert NoRaiseInHandleCall.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoRaiseInHandleCall.match?(diag)
  end

  test "ignores errors" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute NoRaiseInHandleCall.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {17, 5}}
    assert NoRaiseInHandleCall.to_issue(diag).rule == :no_raise_in_handle_call
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoRaiseInHandleCall.to_issue(diag).meta.line == 42
  end
end
