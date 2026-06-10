defmodule Credence.Syntax.PreferDefmoduleWrapperFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.PreferDefmoduleWrapper

  defp analyze(code), do: PreferDefmoduleWrapper.analyze(code)
  defp fix(code), do: PreferDefmoduleWrapper.fix(code)

  test "fixes bare module code by wrapping in defmodule" do
    input = """
    @doc "Returns the maximum value from a list of numbers."
    @spec max_heap_value(list(number())) :: number()
    def max_heap_value([]) do
      raise ArgumentError, "cannot find max of an empty list"
    end

    def max_heap_value(numbers) do
      Enum.max(numbers)
    end
    """

    expected = """
    defmodule Solution do
      @doc "Returns the maximum value from a list of numbers."
      @spec max_heap_value(list(number())) :: number()
      def max_heap_value([]) do
        raise ArgumentError, "cannot find max of an empty list"
      end

      def max_heap_value(numbers) do
        Enum.max(numbers)
      end
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             @doc "Returns the maximum value from a list of numbers."
             @spec max_heap_value(list(number())) :: number()
             def max_heap_value([]) do
               raise ArgumentError, "cannot find max of an empty list"
             end

             def max_heap_value(numbers) do
               Enum.max(numbers)
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             @doc "Returns the maximum value from a list of numbers."
             @spec max_heap_value(list(number())) :: number()
             def max_heap_value([]) do
               raise ArgumentError, "cannot find max of an empty list"
             end

             def max_heap_value(numbers) do
               Enum.max(numbers)
             end
             """)
           )
  end

  test "does not alter code already wrapped in defmodule" do
    code = """
    defmodule Solution do
      def hello, do: :world
    end
    """

    assert fix(code) == code
  end

  test "does not alter simple script code" do
    code = """
    IO.puts("hello")
    """

    assert fix(code) == code
  end
end