defmodule Credence.Semantic.FixPinAtomInExceptionCaseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixPinAtomInExceptionCase

  @real_message "the following clause will never match:\n\n    ^exception\n\nbecause it attempts to match on the result of:\n\n    e\n\nwhich has type:\n\n    %{..., __exception__: true, __struct__: atom()}\n\nwhere \"exception\" was given the type:\n\n    # type: ArgumentError\n    # from: nofile:3:15\n    exception = ArgumentError\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {9, 11}}
    assert FixPinAtomInExceptionCase.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixPinAtomInExceptionCase.match?(diag)
  end

  test "ignores clause-will-never-match without exception context" do
    diag = %{
      severity: :warning,
      message: "the following clause will never match:\n\n    :ok\n\nbecause it attempts to match on the result of:\n\n    x\n\nwhich has type:\n\n    :error\n",
      position: {5, 3}
    }

    refute FixPinAtomInExceptionCase.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {9, 11}}
    assert FixPinAtomInExceptionCase.to_issue(diag).rule == :fix_pin_atom_in_exception_case
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 11}}
    assert FixPinAtomInExceptionCase.to_issue(diag).meta.line == 42
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {9, 11}}
    refute FixPinAtomInExceptionCase.match?(diag)
  end
end
