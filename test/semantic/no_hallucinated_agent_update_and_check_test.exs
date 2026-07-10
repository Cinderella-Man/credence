defmodule Credence.Semantic.NoHallucinatedAgentUpdateAndCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedAgentUpdateAnd

  @warning_message "Agent.update_and/2 is undefined or private. Did you mean:\n\n    * update/2\n    * update/3\n    * update/4\n    * update/5\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @warning_message, position: {3, 11}}
    assert NoHallucinatedAgentUpdateAnd.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedAgentUpdateAnd.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module HallucinatedAgentUpdateAnd (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedAgentUpdateAnd.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @warning_message, position: {3, 11}}
    assert NoHallucinatedAgentUpdateAnd.to_issue(diag).rule == :no_hallucinated_agent_update_and
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @warning_message, position: {42, 10}}
    assert NoHallucinatedAgentUpdateAnd.to_issue(diag).meta.line == 42
  end
end
