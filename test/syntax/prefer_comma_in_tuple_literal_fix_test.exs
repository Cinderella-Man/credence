defmodule Credence.Syntax.PreferCommaInTupleLiteralFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferCommaInTupleLiteral

  defp analyze(code), do: PreferCommaInTupleLiteral.analyze(code)
  defp fix(code), do: PreferCommaInTupleLiteral.fix(code)

  test "fixes the syntax error" do
    input = "{:noreply state}"
    expected = "{:noreply, state}"
    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("{:noreply state}")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("{:noreply state}"))
  end
end
