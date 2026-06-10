defmodule Credence.Semantic.RequireDefmoduleWrapperFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.RequireDefmoduleWrapper

  defp fix(source, message, line \\ 1) do
    RequireDefmoduleWrapper.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    @doc \"""
    Returns the smallest number in a non-empty list of numbers.
    \"""
    @spec smallest_num([number()]) :: number()
    def smallest_num([head | tail]) do
      smallest_num(tail, head)
    end
    """

    expected = """
    defmodule Solution do
    @doc \"""
    Returns the smallest number in a non-empty list of numbers.
    \"""
    @spec smallest_num([number()]) :: number()
    def smallest_num([head | tail]) do
      smallest_num(tail, head)
    end
    end
    """

    message = "cannot invoke @doc/1 outside module"
    assert fix(input, message) == expected
  end

  test "fixed output is well-formed (parses)" do
    message = "cannot invoke @doc/1 outside module"

    assert valid_syntax?(
             fix(
               """
               @doc \"""
               Returns the smallest number in a non-empty list of numbers.
               \"""
               @spec smallest_num([number()]) :: number()
               def smallest_num([head | tail]) do
                 smallest_num(tail, head)
               end
               """,
               message
             )
           )
  end
end