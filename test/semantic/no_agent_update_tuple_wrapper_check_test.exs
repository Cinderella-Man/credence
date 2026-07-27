defmodule Credence.Semantic.NoAgentUpdateTupleWrapperCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoAgentUpdateTupleWrapper

  @match_msg "Agent.update callback should return new state, not {:ok, state}"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @match_msg, position: {11, 7}}
    assert NoAgentUpdateTupleWrapper.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoAgentUpdateTupleWrapper.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_msg, position: {11, 7}}
    assert NoAgentUpdateTupleWrapper.to_issue(diag).rule == :no_agent_update_tuple_wrapper
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @match_msg, position: {42, 5}}
    assert NoAgentUpdateTupleWrapper.to_issue(diag).meta.line == 42
  end
end
