defmodule Credence.Semantic.NoUndefinedModuleInRescueCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUndefinedModuleInRescue

  @real_message "struct NotImplementedError is undefined (module NotImplementedError is not available or is yet to be defined). Make sure the module name is correct and has been specified in full (or that an alias has been defined)"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {104, 9}}
    assert NoUndefinedModuleInRescue.match?(diag)
  end

  test "matches with different undefined module" do
    diag = %{
      severity: :warning,
      message:
        "struct BadStructError is undefined (module BadStructError is not available or is yet to be defined). Make sure the module name is correct and has been specified in full (or that an alias has been defined)",
      position: {5, 3}
    }

    assert NoUndefinedModuleInRescue.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated warning", position: {1, 1}}
    refute NoUndefinedModuleInRescue.match?(diag)
  end

  test "ignores undefined without struct prefix" do
    diag = %{
      severity: :warning,
      message:
        "MyApp.Repo.insert!/1 is undefined (module MyApp.Repo is not available or is yet to be defined)",
      position: {1, 1}
    }

    refute NoUndefinedModuleInRescue.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {104, 9}}
    refute NoUndefinedModuleInRescue.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {104, 9}}
    assert NoUndefinedModuleInRescue.to_issue(diag).rule == :no_undefined_module_in_rescue
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {104, 9}}
    assert NoUndefinedModuleInRescue.to_issue(diag).meta.line == 104
  end

  test "passes through the diagnostic message" do
    diag = %{severity: :warning, message: @real_message, position: {104, 9}}
    assert NoUndefinedModuleInRescue.to_issue(diag).message == @real_message
  end
end
