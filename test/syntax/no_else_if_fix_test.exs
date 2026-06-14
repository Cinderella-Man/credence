defmodule Credence.Syntax.NoElseIfFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoElseIf

  defp analyze(code), do: NoElseIf.analyze(code)
  defp fix(code), do: NoElseIf.fix(code)

  test "fixes the syntax error" do
    input = """
    if n == 0 do
      list
    else if n >= length(list) do
      []
    else
      List.take(list, length(list) - n)
    end
    """

    expected = """
    cond do
      n == 0 -> list
      n >= length(list) -> []
      true -> List.take(list, length(list) - n)
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             if n == 0 do
               list
             else if n >= length(list) do
               []
             else
               List.take(list, length(list) - n)
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             if n == 0 do
               list
             else if n >= length(list) do
               []
             else
               List.take(list, length(list) - n)
             end
             """)
           )
  end
end
