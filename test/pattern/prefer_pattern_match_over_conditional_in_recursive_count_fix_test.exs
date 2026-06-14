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
