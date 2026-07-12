defmodule Credence.Syntax.NoElseInForComprehensionAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoElseInForComprehension

  defp analyze(code), do: NoElseInForComprehension.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_else_in_for_comprehension}] =
             analyze("""
             for x <- [1, 2, 3] do
               x * 2
             else
               _ -> []
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           for x <- [1, 2, 3] do
             x * 2
           end
           """) == []
  end
end
