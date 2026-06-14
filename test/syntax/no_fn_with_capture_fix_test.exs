defmodule Credence.Syntax.NoFnWithCaptureFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoFnWithCapture

  defp fix(code), do: NoFnWithCapture.fix(code)
  defp analyze(code), do: NoFnWithCapture.analyze(code)

  test "rewrites fn( to &( before a capture variable" do
    input = """
    Enum.filter(list, fn(&1 > 0))
    """

    expected = """
    Enum.filter(list, &(&1 > 0))
    """

    assert fix(input) == expected
  end

  test "fixes the call inside a module" do
    input = """
    defmodule Solution do
      def filter_positives(list) do
        Enum.filter(list, fn(&1 > 0))
      end
    end
    """

    expected = """
    defmodule Solution do
      def filter_positives(list) do
        Enum.filter(list, &(&1 > 0))
      end
    end
    """

    assert fix(input) == expected
  end

  test "preserves later capture variables in the body" do
    input = """
    Enum.reduce(list, fn(&1 + &2))
    """

    expected = """
    Enum.reduce(list, &(&1 + &2))
    """

    assert fix(input) == expected
  end

  test "leaves valid parenthesised fn parameters untouched" do
    source = """
    Enum.filter(list, fn(x) -> x > 0 end)
    """

    assert fix(source) == source
  end

  test "leaves an identifier that merely ends in fn untouched" do
    source = """
    myfn(&1 > 0)
    """

    assert fix(source) == source
  end

  test "fix clears the analyze flag (fixpoint)" do
    assert analyze(
             fix("""
             Enum.filter(list, fn(&1 > 0))
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               def filter_positives(list) do
                 Enum.filter(list, fn(&1 > 0))
               end
             end
             """)
           )
  end
end
