defmodule Credence.Semantic.NoImportLocalFunctionConflictCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoImportLocalFunctionConflict

  @real_message "imported StreamData.date/1 conflicts with local function"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {2, 8}, file: "nofile"}
    assert NoImportLocalFunctionConflict.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated error", position: {1, 1}}
    refute NoImportLocalFunctionConflict.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Generators (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoImportLocalFunctionConflict.match?(diag)
  end

  test "does not match to_string conflicts (handled by NoDefineToString)" do
    diag = %{
      severity: :error,
      message: "imported Kernel.to_string/1 conflicts with local function",
      position: {2, 8}
    }

    refute NoImportLocalFunctionConflict.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {2, 8}, file: "nofile"}
    assert NoImportLocalFunctionConflict.to_issue(diag).rule == :no_import_local_function_conflict
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}, file: "nofile"}
    assert NoImportLocalFunctionConflict.to_issue(diag).meta.line == 42
  end
end
