defmodule Credence.Syntax.PreferCommaInTupleLiteralAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferCommaInTupleLiteral

  defp analyze(code), do: PreferCommaInTupleLiteral.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :prefer_comma_in_tuple_literal}] = analyze("{:noreply state}")
  end

  test "leaves good code alone" do
    assert analyze("{:ok, value}") == []
  end
end
