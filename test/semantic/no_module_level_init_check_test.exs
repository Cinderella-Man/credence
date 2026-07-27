defmodule Credence.Semantic.NoModuleLevelInitCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoModuleLevelInit

  @real_message "undefined function init/0 (there is no such import)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {24, 3}}
    assert NoModuleLevelInit.match?(diag)
  end

  test "matches with different undefined message variant" do
    diag = %{
      severity: :error,
      message:
        "undefined function init/0 (expected Factory to define such a function or there is an optional dependency to it)",
      position: {10, 5}
    }

    assert NoModuleLevelInit.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "undefined function start/0", position: {1, 1}}
    refute NoModuleLevelInit.match?(diag)
  end

  test "ignores init with arguments" do
    diag = %{severity: :error, message: "undefined function init/1", position: {1, 1}}
    refute NoModuleLevelInit.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {24, 3}}
    assert NoModuleLevelInit.to_issue(diag).rule == :no_module_level_init
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {24, 3}}
    assert NoModuleLevelInit.to_issue(diag).meta.line == 24
  end

  test "passes through the diagnostic message" do
    diag = %{severity: :error, message: @real_message, position: {24, 3}}
    assert NoModuleLevelInit.to_issue(diag).message == @real_message
  end
end
