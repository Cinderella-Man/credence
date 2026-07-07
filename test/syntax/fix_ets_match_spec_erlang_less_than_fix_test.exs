defmodule Credence.Syntax.FixEtsMatchSpecErlangLessThanFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixEtsMatchSpecErlangLessThan

  defp analyze(code), do: FixEtsMatchSpecErlangLessThan.analyze(code)
  defp fix(code), do: FixEtsMatchSpecErlangLessThan.fix(code)

  test "fixes the syntax error" do
    input = ~S'guards = [{:=<, :"$1", cutoff}]'
    expected = ~S'guards = [{:<=, :"$1", cutoff}]'

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix(~S'guards = [{:=<, :"$1", cutoff}]')) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(~S'guards = [{:=<, :"$1", cutoff}]'))
  end
end
