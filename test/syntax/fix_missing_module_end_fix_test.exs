defmodule Credence.Syntax.FixMissingModuleEndFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

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

    confirm_fix(fix(input), expected)
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

    confirm_fix(fix(input), expected)
  end

  test "appends every missing end when more than 100 blocks are unclosed" do
    input = String.duplicate("if true do\n", 101) <> ":ok\n"
    expected = input <> String.duplicate("end\n", 101)
    emitted = fix(input)

    confirm_fix(emitted, expected)
    assert analyze(emitted) == []
  end

  test "leaves a complete module untouched" do
    source = """
    defmodule Solution do
      def f(x), do: x
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves a mismatched delimiter untouched" do
    source = "Enum.map(list, fn x -> x + 1)"

    confirm_fix(fix(source), source)
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
