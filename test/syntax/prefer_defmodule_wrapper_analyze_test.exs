defmodule Credence.Syntax.PreferDefmoduleWrapperAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferDefmoduleWrapper

  defp analyze(code), do: PreferDefmoduleWrapper.analyze(code)

  test "flags bare module attributes and function definitions" do
    assert [%Issue{rule: :prefer_defmodule_wrapper}] =
             analyze("""
             @doc "Returns the maximum value from a list of numbers."
             @spec max_heap_value(list(number())) :: number()
             def max_heap_value([]) do
               raise ArgumentError, "cannot find max of an empty list"
             end

             def max_heap_value(numbers) do
               Enum.max(numbers)
             end
             """)
  end

  test "flags bare def without module attributes" do
    assert [%Issue{rule: :prefer_defmodule_wrapper}] =
             analyze("""
             def hello, do: :world
             """)
  end

  test "leaves code with defmodule wrapper alone" do
    assert analyze("""
           defmodule Solution do
             @doc "Returns the maximum value from a list of numbers."
             def max_heap_value(numbers) do
               Enum.max(numbers)
             end
           end
           """) == []
  end

  test "leaves simple script code alone" do
    assert analyze("""
           IO.puts("hello")
           """) == []
  end
end