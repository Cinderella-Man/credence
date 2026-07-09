defmodule Credence.Semantic.FixPythonStyleStructDefinitionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixPythonStyleStructDefinition

  @real_message "Node.__struct__/1 is undefined, cannot expand struct Node. Make sure the struct name is correct. If the struct name exists and is correct but it still cannot be found, you likely have cyclic module usage in your code"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {4, 35}}
    assert FixPythonStyleStructDefinition.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute FixPythonStyleStructDefinition.match?(diag)
  end

  test "ignores warning severity" do
    diag = %{severity: :warning, message: @real_message, position: {3, 5}}
    refute FixPythonStyleStructDefinition.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {4, 35}}

    assert FixPythonStyleStructDefinition.to_issue(diag).rule ==
             :fix_python_style_struct_definition
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}}
    assert FixPythonStyleStructDefinition.to_issue(diag).meta.line == 42
  end
end
