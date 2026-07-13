defmodule Credence.Semantic.NoBareFunctionDefSyntaxCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoBareFunctionDefSyntax

  test "matches the diagnostic" do
    diag = %{severity: :error, message: "undefined function init/2 (there is no such import)", position: {7, 3}}
    assert NoBareFunctionDefSyntax.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoBareFunctionDefSyntax.match?(diag)
  end

  test "ignores warnings" do
    diag = %{severity: :warning, message: "undefined function init/2", position: {1, 1}}
    refute NoBareFunctionDefSyntax.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: "undefined function init/2 (there is no such import)", position: {7, 3}}
    issue = NoBareFunctionDefSyntax.to_issue(diag)
    assert issue.rule == :no_bare_function_def_syntax
    assert issue.meta.line == 7
  end

  test "does not match return/1 (hallucinated keyword, not a bare function def)" do
    diag = %{severity: :error, message: "undefined function return/1", position: {4, 7}}
    refute NoBareFunctionDefSyntax.match?(diag)
  end
end
