defmodule Credence.Syntax.FixExtraBraceInEtsMatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixExtraBraceInEtsMatch

  defp analyze(code), do: FixExtraBraceInEtsMatch.analyze(code)
  defp fix(code), do: FixExtraBraceInEtsMatch.fix(code)

  test "fixes the syntax error" do
    input = ~S':ets.match(table, {{name, :"$1"}, :"$2"}})'
    expected = ~S':ets.match(table, {{name, :"$1"}, :"$2"})'

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix(~S':ets.match(table, {{name, :"$1"}, :"$2"}})')) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(~S':ets.match(table, {{name, :"$1"}, :"$2"}})'))
  end
end
