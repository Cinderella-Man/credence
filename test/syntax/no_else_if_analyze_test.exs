defmodule Credence.Syntax.NoElseIfAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoElseIf

  defp analyze(code), do: NoElseIf.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_else_if}] =
             analyze("""
             if n == 0 do
               list
             else if n >= length(list) do
               []
             else
               List.take(list, length(list) - n)
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           cond do
             n == 0 -> list
             n >= length(list) -> []
             true -> List.take(list, length(list) - n)
           end
           """) == []
  end
end
