defmodule Credence.Semantic.FixFunctionInModuleAttributeInlineUsagesCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixFunctionInModuleAttributeInlineUsages

  @match_diag %{
    severity: :error,
    message:
      "cannot inject attribute @default_clock into function/macro because cannot escape " <>
        "#Function<0.118257976 in file:credence_check.ex>. The supported values are: " <>
        "lists, tuples, maps, atoms, numbers, bitstrings, PIDs and remote functions " <>
        "in the format &Mod.fun/arity",
    position: 0,
    file: "credence_check.ex"
  }

  test "matches the diagnostic" do
    assert FixFunctionInModuleAttributeInlineUsages.match?(@match_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixFunctionInModuleAttributeInlineUsages.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixFunctionInModuleAttributeInlineUsages.to_issue(@match_diag).rule ==
             :fix_function_in_module_attribute_inline_usages
  end
end
