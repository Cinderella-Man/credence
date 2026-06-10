defmodule Credence.Syntax.NoEndKeywordVariableAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoEndKeywordVariable

  defp analyze(code), do: NoEndKeywordVariable.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_end_keyword_variable}] =
             analyze("""
             defmodule Solution do
               def calc(a, b) do
                 end = a + b
                 end
               end
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Solution do
             def calc(a, b) do
               result = a + b
               result
             end
           end
           """) == []
  end
end
