defmodule Credence.Syntax.PreferSingleDocAttributeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferSingleDocAttribute

  defp analyze(code), do: PreferSingleDocAttribute.analyze(code)
  defp fix(code), do: PreferSingleDocAttribute.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Solution do
      @doc \"""
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

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               @doc \"""
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
               @doc \"""
               @doc "Returns the length of the longest contiguous subarray."
               def longest_equal_zero_one(list) do
                 :ok
               end
             end
             """)
           )
  end

  test "fixes heredoc with closing triple-quotes" do
    input = """
    defmodule Solution do
      @doc \"\"\"
      @doc "First doc."
      \"\"\"
      @doc "Second doc."
      def hello do
        :ok
      end
    end
    """

    expected = """
    defmodule Solution do
      @doc "Second doc."
      def hello do
        :ok
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed heredoc with closing triple-quotes no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               @doc \"\"\"
               @doc "First doc."
               \"\"\"
               @doc "Second doc."
               def hello do
                 :ok
               end
             end
             """)
           ) == []
  end

  test "fixed heredoc with closing triple-quotes is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               @doc \"\"\"
               @doc "First doc."
               \"\"\"
               @doc "Second doc."
               def hello do
                 :ok
               end
             end
             """)
           )
  end
end
