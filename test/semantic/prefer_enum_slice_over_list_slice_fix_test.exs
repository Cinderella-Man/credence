defmodule Credence.Semantic.PreferEnumSliceOverListSliceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferEnumSliceOverListSlice

  defp fix(source, message, line \\ 3) do
    PreferEnumSliceOverListSlice.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes List.slice to Enum.slice" do
    input = """
    defmodule Solution do
      def safe_slice(list, start, count) do
        List.slice(list, start, count)
      end
    end
    """

    expected = """
    defmodule Solution do
      def safe_slice(list, start, count) do
        Enum.slice(list, start, count)
      end
    end
    """

    message = "List.slice/3 is undefined or private"
    confirm_fix(fix(input, message), expected)
  end

  test "fixed output is well-formed (parses)" do
    message = "List.slice/3 is undefined or private"

    assert valid_syntax?(
             fix(
               """
               defmodule Solution do
                 def safe_slice(list, start, count) do
                   List.slice(list, start, count)
                 end
               end
               """,
               message
             )
           )
  end
end
