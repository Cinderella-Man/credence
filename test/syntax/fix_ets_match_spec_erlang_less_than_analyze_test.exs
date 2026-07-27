defmodule Credence.Syntax.FixEtsMatchSpecErlangLessThanAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixEtsMatchSpecErlangLessThan

  defp analyze(code), do: FixEtsMatchSpecErlangLessThan.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :fix_ets_match_spec_erlang_less_than}] =
             analyze(~S'guards = [{:=<, :"$1", cutoff}]')
  end

  test "leaves good code alone" do
    assert analyze(~S'guards = [{:"=<", :"$1", cutoff}]') == []
  end
end
