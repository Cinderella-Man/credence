defmodule Credence.Syntax.NoReservedWordVariableAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoReservedWordVariable

  defp analyze(code), do: NoReservedWordVariable.analyze(code)

  test "flags reserved word used as variable in tuple pattern" do
    assert [%Issue{rule: :no_reserved_word_variable}] =
             analyze("""
             {before, after} = Enum.split(list, index)
             """)
  end

  test "flags multiple reserved words" do
    issues = analyze("""
    {before, after} = Enum.split(list, index)
    result = if condition do
      before ++ Enum.reverse(after)
    else
      after
    end
    """)
    
    assert length(issues) >= 1
    assert Enum.any?(issues, &(&1.rule == :no_reserved_word_variable))
  end

  test "leaves good code alone" do
    assert analyze("""
           {before, after_val} = Enum.split(list, index)
           before ++ Enum.reverse(after_val)
           """) == []
  end
end
