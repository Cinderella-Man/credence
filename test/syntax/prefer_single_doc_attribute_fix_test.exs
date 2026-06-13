defmodule Credence.Syntax.PreferSingleDocAttributeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.PreferSingleDocAttribute

  defp analyze(code), do: PreferSingleDocAttribute.analyze(code)
  defp fix(code), do: PreferSingleDocAttribute.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Solution do
      @doc """
      @doc "Returns the length of the longest contiguous subarray."
      def longest_equal_zero_one(list) do
        :ok
      end
    end
    """

    expected = """
    defmodule Solution do
      @doc "Returns the length of the longest contiguous subarray."
      def longest_equal_zero_one(list) do
        :ok
      end
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               @doc """
               @doc "Returns the length of the longest contiguous subarray."
               def longest_equal_zero_one(list) do
                 :ok
               end
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               @doc """
               @doc "Returns the length of the longest contiguous subarray."
               def longest_equal_zero_one(list) do
                 :ok
               end
             end
             """)
           )
  end
end
