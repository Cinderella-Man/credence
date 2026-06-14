defmodule Credence.Syntax.NoUnclosedFnDelimiterFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoUnclosedFnDelimiter

  defp fix(code), do: NoUnclosedFnDelimiter.fix(code)
  defp analyze(code), do: NoUnclosedFnDelimiter.analyze(code)

  test "inserts end before the offending )" do
    input = "list |> Enum.max_by(fn {_, second} -> second)"

    expected = "list |> Enum.max_by(fn {_, second} -> second end)"

    confirm_fix(fix(input), expected)
  end

  test "fixes the call inside a module" do
    input = """
    defmodule Solution do
      def top(list) do
        list |> Enum.max_by(fn {_, second} -> second)
      end
    end
    """

    expected = """
    defmodule Solution do
      def top(list) do
        list |> Enum.max_by(fn {_, second} -> second end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "handles a body that itself contains parentheses" do
    input = "Enum.reduce(list, acc, fn x, a -> merge(x, a))"

    expected = "Enum.reduce(list, acc, fn x, a -> merge(x, a) end)"

    confirm_fix(fix(input), expected)
  end

  test "repairs more than one unclosed fn in the same source" do
    input = """
    defmodule Solution do
      def a(list), do: Enum.map(list, fn x -> x + 1)
      def b(list), do: Enum.filter(list, fn x -> x > 0)
    end
    """

    expected = """
    defmodule Solution do
      def a(list), do: Enum.map(list, fn x -> x + 1 end)
      def b(list), do: Enum.filter(list, fn x -> x > 0 end)
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves properly closed code untouched" do
    source = "list |> Enum.map(fn x -> x + 1 end) |> Enum.sum()"

    confirm_fix(fix(source), source)
  end

  test "leaves a different mismatched delimiter untouched" do
    source = "value = [1, 2, 3)"

    confirm_fix(fix(source), source)
  end

  test "fix clears the analyze flag (fixpoint)" do
    assert analyze(fix("list |> Enum.max_by(fn {_, second} -> second)")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               def top(list) do
                 list |> Enum.max_by(fn {_, second} -> second)
               end
             end
             """)
           )
  end
end
