defmodule Credence.Syntax.PreferRecursionOverWhileFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferRecursionOverWhile

  defp analyze(code), do: PreferRecursionOverWhile.analyze(code)
  defp fix(code), do: PreferRecursionOverWhile.fix(code)

  test "fixes a while loop inside a module" do
    input = """
    defmodule Solution do
      def example(list) do
        result = []
        idx = 0
        while idx < length(list) do
          result = result ++ [Enum.at(list, idx)]
          idx = idx + 1
        end
        result
      end
    end
    """

    expected = """
    defmodule Solution do
      def example(list) do
        do_example(list, [], 0)
        result
      end
      defp do_example(list, result, idx) when !(idx < length(list)), do: []
      defp do_example(list, result, idx) do
        result = result ++ [Enum.at(list, idx)]
        idx = idx + 1
        do_example(list, result, idx)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes a bare while loop" do
    input = """
    while idx < 10 do
      idx = idx + 1
    end
    """

    expected = """
    do_loop(nil)

    defp do_loop(idx) when !(idx < 10), do: nil
    defp do_loop(idx) do
      idx = idx + 1
      do_loop(idx)
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             while idx < 10 do
               idx = idx + 1
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             while idx < 10 do
               idx = idx + 1
             end
             """)
           )
  end
end
