defmodule Credence.Semantic.NoCompileWarnUndefinedModuleCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoCompileWarnUndefinedModule

  @real_message "MyApp.Repo.insert!/1 is undefined (module MyApp.Repo is not available or is yet to be defined)"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {118, 16}}
    assert NoCompileWarnUndefinedModule.match?(diag)
  end

  test "matches with different module and function" do
    diag = %{
      severity: :warning,
      message: "SomeOther.Mod.func/2 is undefined (module SomeOther.Mod is not available or is yet to be defined)",
      position: {5, 3}
    }

    assert NoCompileWarnUndefinedModule.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated warning", position: {1, 1}}
    refute NoCompileWarnUndefinedModule.match?(diag)
  end

  test "ignores is undefined without the module suffix" do
    diag = %{severity: :warning, message: "Foo.bar/1 is undefined or private", position: {1, 1}}
    refute NoCompileWarnUndefinedModule.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {118, 16}}
    refute NoCompileWarnUndefinedModule.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {118, 16}}
    assert NoCompileWarnUndefinedModule.to_issue(diag).rule == :no_compile_warn_undefined_module
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {118, 16}}
    assert NoCompileWarnUndefinedModule.to_issue(diag).meta.line == 118
  end
end
