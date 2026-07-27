defmodule Credence.Semantic.NoHallucinatedGuardFnCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedGuardFn

  @real_message "cannot find or invoke local is_regex/1 inside a guard. Only macros can be invoked inside a guard and they must be defined before their invocation. Called as: is_regex(format)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {2, 33}, file: "credence_check.ex"}
    assert NoHallucinatedGuardFn.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoHallucinatedGuardFn.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedGuardFn.match?(diag)
  end

  test "ignores undefined function for other names" do
    diag = %{
      severity: :error,
      message:
        "cannot find or invoke local is_foo/1 inside a guard. Only macros can be invoked inside a guard and they must be defined before their invocation. Called as: is_foo(x)",
      position: {2, 33}
    }

    refute NoHallucinatedGuardFn.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {2, 33}, file: "credence_check.ex"}
    assert NoHallucinatedGuardFn.to_issue(diag).rule == :no_hallucinated_guard_fn
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}, file: "credence_check.ex"}
    assert NoHallucinatedGuardFn.to_issue(diag).meta.line == 42
  end
end
