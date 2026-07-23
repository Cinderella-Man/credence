defmodule Credence.Semantic.NoDefineMatchFnCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDefineMatchFn

  @real_message "imported Kernel.match?/2 conflicts with local function"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {2, 8}, file: "nofile"}
    assert NoDefineMatchFn.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoDefineMatchFn.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Anonymizer (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoDefineMatchFn.match?(diag)
  end

  test "ignores other Kernel-conflict diagnostics owned by sibling rules" do
    # `max/2`, `min/2`, `node/0` conflicts are handled by other rules and this
    # rule's fix cannot repair them, so the check must not claim them.
    for other <- [
          "imported Kernel.max/2 conflicts with local function",
          "imported Kernel.min/2 conflicts with local function",
          "imported Kernel.node/0 conflicts with local function"
        ] do
      refute NoDefineMatchFn.match?(%{severity: :error, message: other, position: {1, 1}})
    end
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {2, 8}, file: "nofile"}
    assert NoDefineMatchFn.to_issue(diag).rule == :no_define_match_fn
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}, file: "nofile"}
    assert NoDefineMatchFn.to_issue(diag).meta.line == 42
  end
end
