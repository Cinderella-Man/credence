defmodule Credence.Syntax.NoWhileKeywordFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoWhileKeyword

  defp analyze(code), do: NoWhileKeyword.analyze(code)
  defp fix(code), do: NoWhileKeyword.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Solution do
      def sum_while(list) do
        result = 0
        i = 0
        while i < length(list) do
          result = result + Enum.at(list, i)
          i = i + 1
        end
        result
      end
    end
    """

    expected = """
    defmodule Solution do
      def sum_while(list) do
        do_sum_while(list, 0, 0)
      end
      defp do_sum_while(list, _i, result), do: result
      defp do_sum_while(list, i, result) when i < length(list) do
        result = result + Enum.at(list, i)
        i = i + 1
        do_sum_while(list, i, result)
      end
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               def sum_while(list) do
                 result = 0
                 i = 0
                 while i < length(list) do
                   result = result + Enum.at(list, i)
                   i = i + 1
                 end
                 result
               end
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               def sum_while(list) do
                 result = 0
                 i = 0
                 while i < length(list) do
                   result = result + Enum.at(list, i)
                   i = i + 1
                 end
                 result
               end
             end
             """)
           )
  end
end
