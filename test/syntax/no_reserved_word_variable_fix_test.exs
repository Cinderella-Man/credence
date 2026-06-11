defmodule Credence.Syntax.NoReservedWordVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoReservedWordVariable

  defp analyze(code), do: NoReservedWordVariable.analyze(code)
  defp fix(code), do: NoReservedWordVariable.fix(code)

  test "fixes the syntax error" do
    input = """
    {before, after} = Enum.split(list, index)
    before ++ Enum.reverse(after)
    """

    expected = """
    {before, after_val} = Enum.split(list, index)
    before ++ Enum.reverse(after_val)
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             {before, after} = Enum.split(list, index)
             before ++ Enum.reverse(after)
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    # the repaired source must be valid Elixir
    assert valid_syntax?(
             fix("""
             {before, after} = Enum.split(list, index)
             before ++ Enum.reverse(after)
             """)
           )
  end

  test "preserves end keyword and :end atom when renaming end variable" do
    input = """
    defmodule Solution do
      def test do
        Enum.flat_map([{:a, :b}], fn {start, end} ->
          [{start, :start}, {end, :end}]
        end)
      end
    end
    """

    expected = """
    defmodule Solution do
      def test do
        Enum.flat_map([{:a, :b}], fn {start, end_val} ->
          [{start, :start}, {end_val, :end}]
        end)
      end
    end
    """

    assert fix(input) == expected
  end

  test "fixed output with end variable parses correctly" do
    input = """
    defmodule Solution do
      def test do
        Enum.flat_map([{:a, :b}], fn {start, end} ->
          [{start, :start}, {end, :end}]
        end)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
