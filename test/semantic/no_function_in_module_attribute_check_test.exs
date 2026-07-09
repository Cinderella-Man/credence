defmodule Credence.Semantic.NoFunctionInModuleAttributeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoFunctionInModuleAttribute

  @match_diag %{
    severity: :error,
    message:
      "cannot inject attribute @default_processor into function/macro because cannot escape " <>
        "#Function<0.118257976 in file:credence_check.ex>. The supported values are: " <>
        "lists, tuples, maps, atoms, numbers, bitstrings, PIDs and remote functions " <>
        "in the format &Mod.fun/arity",
    position: 0,
    file: "credence_check.ex"
  }

  test "matches the diagnostic" do
    assert NoFunctionInModuleAttribute.match?(@match_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoFunctionInModuleAttribute.match?(diag)
  end

  test "ignores generic cannot-escape without attribute injection" do
    diag = %{severity: :error, message: "cannot escape #Function<...>", position: {1, 1}}
    refute NoFunctionInModuleAttribute.match?(diag)
  end

  test "ignores attribute injection without function escape" do
    diag = %{severity: :error, message: "cannot inject attribute @foo", position: {1, 1}}
    refute NoFunctionInModuleAttribute.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoFunctionInModuleAttribute.to_issue(@match_diag).rule ==
             :no_function_in_module_attribute
  end
end
