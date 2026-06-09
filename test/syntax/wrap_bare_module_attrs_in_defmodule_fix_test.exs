defmodule Credence.Syntax.WrapBareModuleAttrsInDefmoduleFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.WrapBareModuleAttrsInDefmodule

  defp analyze(code), do: WrapBareModuleAttrsInDefmodule.analyze(code)
  defp fix(code), do: WrapBareModuleAttrsInDefmodule.fix(code)

  test "fixes bare module attrs by wrapping in defmodule" do
    input = """
    @doc "Checks if a list is a palindrome."
    @spec palindrome_list?(list()) :: boolean()
    def palindrome_list?([]), do: true
    def palindrome_list?([_]), do: true
    def palindrome_list?(list) do
      list == Enum.reverse(list)
    end
    """

    expected = """
    defmodule Solution do
      @doc "Checks if a list is a palindrome."
      @spec palindrome_list?(list()) :: boolean()
      def palindrome_list?([]), do: true
      def palindrome_list?([_]), do: true
      def palindrome_list?(list) do
        list == Enum.reverse(list)
      end
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             @doc "Checks if a list is a palindrome."
             @spec palindrome_list?(list()) :: boolean()
             def palindrome_list?([]), do: true
             def palindrome_list?([_]), do: true
             def palindrome_list?(list) do
               list == Enum.reverse(list)
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             @doc "Checks if a list is a palindrome."
             @spec palindrome_list?(list()) :: boolean()
             def palindrome_list?([]), do: true
             def palindrome_list?([_]), do: true
             def palindrome_list?(list) do
               list == Enum.reverse(list)
             end
             """)
           )
  end
end