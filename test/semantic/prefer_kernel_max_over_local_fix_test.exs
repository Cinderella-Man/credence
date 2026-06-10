defmodule Credence.Semantic.PreferKernelMaxOverLocalFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.PreferKernelMaxOverLocal

  defp fix(source, message, line \\ 1) do
    PreferKernelMaxOverLocal.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "removes local defp max/2 that shadows Kernel.max/2" do
    input = """
    defmodule Solution do
      def calculate do
        max(3, 5)
      end

      defp max(a, b) when a >= b, do: a
      defp max(a, b) when b > a, do: b
    end
    """

    expected = """
    defmodule Solution do
      def calculate do
        max(3, 5)
      end
    end
    """

    message = "imported Kernel.max/2 conflicts with local function"
    assert fix(input, message) == expected
  end

  test "fixed output is well-formed (parses)" do
    message = "imported Kernel.max/2 conflicts with local function"

    assert valid_syntax?(
             fix(
               """
               defmodule Solution do
                 def calculate do
                   max(3, 5)
                 end

                 defp max(a, b) when a >= b, do: a
                 defp max(a, b) when b > a, do: b
               end
               """,
               message
             )
           )
  end
end
