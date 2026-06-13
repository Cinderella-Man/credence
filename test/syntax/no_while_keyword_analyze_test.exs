defmodule Credence.Syntax.NoWhileKeywordAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoWhileKeyword

  defp analyze(code), do: NoWhileKeyword.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_while_keyword}] =
             analyze("""
             while i < 10 do
               i = i + 1
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           def example(list) do
             Enum.each(list, fn x -> IO.puts(x) end)
           end
           """) == []
  end
end
