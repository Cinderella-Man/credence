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
        Kernel.max(3, 5)
      end
    end
    """

    message = "imported Kernel.max/2 conflicts with local function"
    assert fix(input, message) == expected
  end

  test "removes local defp is_nil/1 that shadows Kernel.is_nil/1 and qualifies calls" do
    input = """
    defmodule Problematic do
      defp is_nil(nil), do: true
      defp is_nil(_other), do: false

      def check_value(map, key) do
        value = Map.get(map, key)

        if is_nil(value) do
          :missing
        else
          {:ok, value}
        end
      end
    end
    """

    expected = """
    defmodule Problematic do
      def check_value(map, key) do
        value = Map.get(map, key)

        if Kernel.is_nil(value) do
          :missing
        else
          {:ok, value}
        end
      end
    end
    """

    message = "imported Kernel.is_nil/1 conflicts with local function"
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

  test "is_nil fix output is well-formed (parses)" do
    message = "imported Kernel.is_nil/1 conflicts with local function"

    assert valid_syntax?(
             fix(
               """
               defmodule Problematic do
                 defp is_nil(nil), do: true
                 defp is_nil(_other), do: false

                 def check_value(map, key) do
                   value = Map.get(map, key)

                   if is_nil(value) do
                     :missing
                   else
                     {:ok, value}
                   end
                 end
               end
               """,
               message
             )
           )
  end
end
