defmodule Credence.Syntax.FixExtraBraceInEtsMatchAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixExtraBraceInEtsMatch

  defp analyze(code), do: FixExtraBraceInEtsMatch.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :fix_extra_brace_in_ets_match}] =
             analyze(~S':ets.match(table, {{name, :"$1"}, :"$2"}})')
  end

  test "leaves good code alone" do
    assert analyze(~S':ets.match(table, {{name, :"$1"}, :"$2"})') == []
  end
end
