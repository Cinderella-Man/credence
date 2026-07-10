defmodule Credence.Semantic.FixBitwiseInfixOperatorCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixBitwiseInfixOperator

  @real_diag %{
    severity: :error,
    message:
      "invalid syntax found on credence_check.ex:190:45:\n     error: syntax error before: '>'\n     │\n 190 │     do_secure_compare(ta, tb, acc ||| (ha <-> hb))\n     │                                             ^\n     │\n     └─ credence_check.ex:190:45",
    position: 190,
    file: "credence_check.ex"
  }

  @xor_diag %{
    severity: :error,
    message:
      "invalid syntax found on example.ex:3:20:\n     error: syntax error before: '^'\n     │\n   3 │     diff = a ^^^ b\n     │                    ^\n     │\n     └─ example.ex:3:20",
    position: {3, 20}
  }

  test "matches the real diagnostic" do
    assert FixBitwiseInfixOperator.match?(@real_diag)
  end

  test "matches the ^^^ diagnostic" do
    assert FixBitwiseInfixOperator.match?(@xor_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixBitwiseInfixOperator.match?(diag)
  end

  test "ignores generic syntax error without bitwise operator" do
    diag = %{severity: :error, message: "syntax error before: ')'", position: {1, 1}}
    refute FixBitwiseInfixOperator.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixBitwiseInfixOperator.to_issue(@real_diag).rule == :fix_bitwise_infix_operator
  end

  test "issue message mentions the operator" do
    assert FixBitwiseInfixOperator.to_issue(@real_diag).message =~ "|||"
  end

  test "issue message mentions Bitwise" do
    assert FixBitwiseInfixOperator.to_issue(@real_diag).message =~ "Bitwise"
  end
end
