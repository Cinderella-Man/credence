defmodule Credence.Pattern.PreferPatternMatchOverConditionalInRecursiveCountFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPatternMatchOverConditionalInRecursiveCount

  test "rewrites the anti-pattern" do
    input = """
    defmodule Example do
      def count_until([], _target, _stop), do: 0
      def count_until([stop | _rest], _target, stop), do: 0
      def count_until([head | tail], target, stop) do
        count = if head == target, do: 1, else: 0
        count + count_until(tail, target, stop)
      end
    end
    """

    expected = """
    defmodule Example do
      def count_until([], _target, _stop), do: 0
      def count_until([stop | _rest], _target, stop), do: 0
      def count_until([head | tail], target, stop) when head == target,
        do: 1 + count_until(tail, target, stop)
      def count_until([_ | tail], target, stop), do: count_until(tail, target, stop)
    end
    """

    confirm_fix(fix(PreferPatternMatchOverConditionalInRecursiveCount, input), expected)
  end

  test "rewrites without stop parameter" do
    input = """
    defmodule Example do
      def count([], _target), do: 0
      def count([head | tail], target) do
        count = if head == target, do: 1, else: 0
        count + count(tail, target)
      end
    end
    """

    expected = """
    defmodule Example do
      def count([], _target), do: 0
      def count([head | tail], target) when head == target, do: 1 + count(tail, target)
      def count([_ | tail], target), do: count(tail, target)
    end
    """

    confirm_fix(fix(PreferPatternMatchOverConditionalInRecursiveCount, input), expected)
  end

  test "preserves the strict equality operator in the guard" do
    input = """
    defmodule Example do
      def count([], _target), do: 0
      def count([head | tail], target) do
        count = if head === target, do: 1, else: 0
        count + count(tail, target)
      end
    end
    """

    expected = """
    defmodule Example do
      def count([], _target), do: 0
      def count([head | tail], target) when head === target, do: 1 + count(tail, target)
      def count([_ | tail], target), do: count(tail, target)
    end
    """

    confirm_fix(fix(PreferPatternMatchOverConditionalInRecursiveCount, input), expected)
  end

  test "leaves a body with an extra statement untouched (would drop it)" do
    code = """
    defmodule Example do
      def count([], _target), do: 0
      def count([head | tail], target) do
        count = if head == target, do: 1, else: 0
        IO.puts(head)
        count + count(tail, target)
      end
    end
    """

    confirm_fix(fix(PreferPatternMatchOverConditionalInRecursiveCount, code), code)
  end

  test "leaves recursion with differing args untouched (would break the head)" do
    code = """
    defmodule Example do
      def count([], _target, _acc), do: 0
      def count([head | tail], target, acc) do
        count = if head == target, do: 1, else: 0
        count + count(tail, target, acc + 1)
      end
    end
    """

    confirm_fix(fix(PreferPatternMatchOverConditionalInRecursiveCount, code), code)
  end

  test "leaves a count variable that rebinds a remaining parameter untouched" do
    code = """
    defmodule RecursiveCountReboundParameterFixture do
      def count([], target), do: target
      def count([head | tail], target) do
        target = if head == target, do: 1, else: 0
        target + count(tail, target)
      end
    end
    """

    confirm_fix(fix(PreferPatternMatchOverConditionalInRecursiveCount, code), code)
  end

  test "does not modify code without the anti-pattern" do
    code = """
    defmodule Example do
      def count_until([], _target, _stop), do: 0
      def count_until([stop | _rest], _target, stop), do: 0
      def count_until([target | tail], target, stop), do: 1 + count_until(tail, target, stop)
      def count_until([_head | tail], target, stop), do: count_until(tail, target, stop)
    end
    """

    confirm_fix(fix(PreferPatternMatchOverConditionalInRecursiveCount, code), code)
  end
end
