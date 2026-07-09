defmodule Credence.Semantic.NoPlugBeforeDependencyDefinitionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoPlugBeforeDependencyDefinition

  @matching_diag %{
    severity: :error,
    message:
      "invalid syntax found on credence_check.ex:7:22:\n    error: atom cannot be followed by an alias. If the '.' was meant to be part of the atom's name, the atom name must be quoted. Syntax error before: '.'\n    │\n  7 │   plug(:LifecycleApi.Plugs.ApiVersion, default: \"v2\")\n    │                      ^\n    └─ credence_check.ex:7:22",
    position: 7,
    file: "credence_check.ex"
  }

  test "matches the diagnostic" do
    assert NoPlugBeforeDependencyDefinition.match?(@matching_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoPlugBeforeDependencyDefinition.match?(diag)
  end

  test "ignores generic undefined function without module-not-available" do
    diag = %{severity: :error, message: "undefined function foo/1", position: 1}
    refute NoPlugBeforeDependencyDefinition.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoPlugBeforeDependencyDefinition.to_issue(@matching_diag).rule ==
             :no_plug_before_dependency_definition
  end
end
