defmodule Credence.Semantic.NoDefineToStringCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDefineToString

  @real_message "imported Kernel.to_string/1 conflicts with local function"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {2, 8}, file: "nofile"}
    assert NoDefineToString.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoDefineToString.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Anonymizer (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoDefineToString.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {2, 8}, file: "nofile"}
    assert NoDefineToString.to_issue(diag).rule == :no_define_to_string
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}, file: "nofile"}
    assert NoDefineToString.to_issue(diag).meta.line == 42
  end
end
