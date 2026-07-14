defmodule Credence.Semantic.FixUndefinedNestedModuleStructCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUndefinedNestedModuleStruct

  @matching_diag %{
    severity: :error,
    message:
      "AutocompleteTrie.Node.__struct__/1 is undefined (module AutocompleteTrie.Node is not available)",
    position: {5, 5}
  }

  test "matches the diagnostic" do
    assert FixUndefinedNestedModuleStruct.match?(@matching_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixUndefinedNestedModuleStruct.match?(diag)
  end

  test "ignores generic undefined without module-not-available" do
    diag = %{severity: :error, message: "undefined function foo/1", position: {1, 1}}
    refute FixUndefinedNestedModuleStruct.match?(diag)
  end

  test "ignores non-struct module-not-available" do
    diag = %{
      severity: :error,
      message:
        "function Foo.Bar.init/1 is undefined (module Foo.Bar is not available)",
      position: {1, 1}
    }

    refute FixUndefinedNestedModuleStruct.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixUndefinedNestedModuleStruct.to_issue(@matching_diag).rule ==
             :fix_undefined_nested_module_struct
  end
end
