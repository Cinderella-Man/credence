defmodule Credence.Syntax.FixMissingModuleEndFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.FixMissingModuleEnd

  defp fix(code), do: FixMissingModuleEnd.fix(code)
  defp analyze(code), do: FixMissingModuleEnd.analyze(code)

  test "appends the missing module end" do
    input = """
    defmodule Solution do
      def calculate(earth_weight) do
        earth_weight * 2
      end
    """

    expected = """
    defmodule Solution do
      def calculate(earth_weight) do
        earth_weight * 2
      end
    end
    """

    assert fix(input) == expected
  end

  test "appends several ends when multiple blocks are unclosed" do
    input = """
    defmodule Solution do
      def f do
        1
    """

    expected = """
    defmodule Solution do
      def f do
        1
    end
    end
    """

    assert fix(input) == expected
  end

  test "leaves a complete module untouched" do
    source = """
    defmodule Solution do
      def f(x), do: x
    end
    """

    assert fix(source) == source
  end

  test "leaves a mismatched delimiter untouched" do
    source = """
    Enum.map(list, fn x -> x + 1)
    """

    assert fix(source) == source
  end

  test "fix clears the analyze flag (fixpoint)" do
    assert analyze(
             fix("""
             defmodule Solution do
               def f(x), do: x
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               def calculate(earth_weight) do
                 earth_weight * 2
               end
             """)
           )
  end
end
