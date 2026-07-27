defmodule Credence.Semantic.FixPlugDependencyModuleOrderCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixPlugDependencyModuleOrder

  @matching_diag %{
    severity: :error,
    message:
      "function MediaVersionApi.Plugs.AcceptVersion.init/1 is undefined (module MediaVersionApi.Plugs.AcceptVersion is not available)",
    position: 0,
    file: "credence_check.ex"
  }

  test "matches the diagnostic" do
    assert FixPlugDependencyModuleOrder.match?(@matching_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixPlugDependencyModuleOrder.match?(diag)
  end

  test "ignores generic undefined function without module-not-available" do
    diag = %{severity: :error, message: "undefined function foo/1", position: 1}
    refute FixPlugDependencyModuleOrder.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixPlugDependencyModuleOrder.to_issue(@matching_diag).rule ==
             :fix_plug_dependency_module_order
  end
end
