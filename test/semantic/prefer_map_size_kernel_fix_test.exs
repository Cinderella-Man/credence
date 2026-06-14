defmodule Credence.Semantic.PreferMapSizeKernelFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferMapSizeKernel

  defp fix(source, message, line \\ 3) do
    PreferMapSizeKernel.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes Map.size to map_size" do
    input = """
    defmodule Solution do
      def size_of(map) do
        Map.size(map)
      end
    end
    """

    expected = """
    defmodule Solution do
      def size_of(map) do
        map_size(map)
      end
    end
    """

    message = "Map.size/1 is deprecated. Use map_size/1 instead."
    confirm_fix(fix(input, message), expected)
  end

  test "fixed output is well-formed (parses)" do
    message = "Map.size/1 is deprecated. Use map_size/1 instead."

    assert valid_syntax?(
             fix(
               """
               defmodule Solution do
                 def size_of(map) do
                   Map.size(map)
                 end
               end
               """,
               message
             )
           )
  end
end
