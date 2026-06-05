defmodule Credence.Pattern.NoListDeleteAtWithLengthFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListDeleteAtWithLength
  alias Credence.RuleHelpers

  defp fix(source), do: RuleHelpers.apply_rule_fix(NoListDeleteAtWithLength, source)

  test "rewrites length(x) - 1 to the negative index -1" do
    code = """
    defmodule M do
      def drop_last(list) do
        List.delete_at(list, length(list) - 1)
      end
    end
    """

    expected = """
    defmodule M do
      def drop_last(list) do
        List.delete_at(list, -1)
      end
    end
    """

    assert fix(code) == expected
  end

  test "rewrites Kernel.length(x) - 1 to the negative index -1" do
    code = """
    defmodule M do
      def drop_last(list) do
        List.delete_at(list, Kernel.length(list) - 1)
      end
    end
    """

    expected = """
    defmodule M do
      def drop_last(list) do
        List.delete_at(list, -1)
      end
    end
    """

    assert fix(code) == expected
  end

  test "rewrites only the delete_at call, leaving siblings untouched" do
    code = """
    defmodule Solution do
      def swap_head_tail(list) do
        [head | tail] = list
        last = List.last(tail)
        middle = List.delete_at(tail, length(tail) - 1)
        [last | middle] ++ [head]
      end
    end
    """

    expected = """
    defmodule Solution do
      def swap_head_tail(list) do
        [head | tail] = list
        last = List.last(tail)
        middle = List.delete_at(tail, -1)
        [last | middle] ++ [head]
      end
    end
    """

    assert fix(code) == expected
  end

  test "leaves offset of 2 unchanged (not equivalent to -2)" do
    code = """
    defmodule M do
      def drop(list) do
        List.delete_at(list, length(list) - 2)
      end
    end
    """

    assert fix(code) == code
  end

  test "leaves a plain literal index unchanged" do
    code = """
    defmodule M do
      def drop(list) do
        List.delete_at(list, 0)
      end
    end
    """

    assert fix(code) == code
  end

  test "leaves a different length variable unchanged" do
    code = """
    defmodule M do
      def drop(list, other) do
        List.delete_at(list, length(other) - 1)
      end
    end
    """

    assert fix(code) == code
  end
end
