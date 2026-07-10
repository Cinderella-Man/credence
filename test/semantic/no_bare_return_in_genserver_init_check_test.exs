defmodule Credence.Semantic.NoBareReturnInGenserverInitCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoBareReturnInGenserverInit

  @match_msg "init/1 must return {:ok, state}"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @match_msg, position: {9, 5}}
    assert NoBareReturnInGenserverInit.match?(diag)
  end

  test "matches when message contains the substring" do
    diag = %{severity: :warning, message: "warning: #{@match_msg}", position: {1, 1}}
    assert NoBareReturnInGenserverInit.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoBareReturnInGenserverInit.match?(diag)
  end

  test "ignores errors" do
    diag = %{severity: :error, message: @match_msg, position: {1, 1}}
    refute NoBareReturnInGenserverInit.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_msg, position: {9, 5}}
    assert NoBareReturnInGenserverInit.to_issue(diag).rule == :no_bare_return_in_genserver_init
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @match_msg, position: {42, 10}}
    assert NoBareReturnInGenserverInit.to_issue(diag).meta.line == 42
  end
end
