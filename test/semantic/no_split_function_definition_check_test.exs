defmodule Credence.Semantic.NoSplitFunctionDefinitionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoSplitFunctionDefinition

  @split_msg "function handle_call/3 has multiple clauses and they are not adjacent"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @split_msg, position: {17, 1}}
    assert NoSplitFunctionDefinition.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoSplitFunctionDefinition.match?(diag)
  end

  test "ignores errors (this is a warning)" do
    diag = %{severity: :error, message: @split_msg, position: {17, 1}}
    refute NoSplitFunctionDefinition.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @split_msg, position: {17, 1}}
    issue = NoSplitFunctionDefinition.to_issue(diag)
    assert issue.rule == :no_split_function_definition
    assert issue.meta.line == 17
  end
end
