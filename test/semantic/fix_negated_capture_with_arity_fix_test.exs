defmodule Credence.Semantic.FixNegatedCaptureWithArityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixNegatedCaptureWithArity

  @not_message "invalid args for &, expected one of:\n\n  * &Mod.fun/arity to capture a remote function, such as &Enum.map/2\n  * &fun/arity to capture a local or imported function, such as &is_atom/1\n  * &some_code(&1, ...) containing at least one argument as &1, such as &List.flatten(&1)\n\nGot: not Enum.empty?() / 1"

  defp fix(source, message, line \\ 1) do
    FixNegatedCaptureWithArity.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes &(!fn/arity) to &(!fn(&1))" do
    input = "Enum.any?(list, &(!Enum.empty?/1))"
    expected = "Enum.any?(list, &(!Enum.empty?(&1)))"
    message = "invalid args for &"
    confirm_fix(fix(input, message), expected)
  end

  test "fixes &(not fn/arity) to &(not fn(&1))" do
    input = "Enum.any?(list, &(not Enum.empty?/1))"
    expected = "Enum.any?(list, &(not Enum.empty?(&1)))"
    confirm_fix(fix(input, @not_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    message = "invalid args for &"
    assert valid_syntax?(fix("Enum.any?(list, &(!Enum.empty?/1))", message))
  end
end
