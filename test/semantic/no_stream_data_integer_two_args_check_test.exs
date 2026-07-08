defmodule Credence.Semantic.NoStreamDataIntegerTwoArgsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoStreamDataIntegerTwoArgs

  @real_message "function StreamData.__using__/1 is undefined or private"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: 0}
    assert NoStreamDataIntegerTwoArgs.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoStreamDataIntegerTwoArgs.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0
    }

    refute NoStreamDataIntegerTwoArgs.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: 0}
    assert NoStreamDataIntegerTwoArgs.to_issue(diag).rule == :no_stream_data_integer_two_args
  end

  test "preserves the line in the issue" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoStreamDataIntegerTwoArgs.to_issue(diag).meta.line == 42
  end
end
