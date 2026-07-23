defmodule Credence.Semantic.FixFnGuardPositionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.FixFnGuardPosition

  @real_message "cannot find or invoke local when/2 inside a match. Only macros can be invoked inside a match and they must be defined before their invocation. Called as: {[second], count} when second > cutoff"

  defp fix(source, message \\ @real_message, line \\ 1) do
    FixFnGuardPosition.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "moves misplaced when guard after all fn arguments" do
    input = """
    defmodule M do
      def sum_above(list, cutoff) do
        Enum.reduce(list, 0, fn
          {key, val} when key > cutoff, acc -> acc + val
          _, acc -> acc
        end)
      end
    end
    """

    expected = """
    defmodule M do
      def sum_above(list, cutoff) do
        Enum.reduce(list, 0, fn
          {key, val}, acc when key > cutoff -> acc + val
          _, acc -> acc
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "moves a when misplaced on a middle argument after all arguments" do
    input = """
    defmodule M do
      def make do
        fn a, b when is_integer(b), c -> a + b + c end
      end
    end
    """

    expected = """
    defmodule M do
      def make do
        fn a, b, c when is_integer(b) -> a + b + c end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed flagship output compiles" do
    input = """
    defmodule CredenceFnGuardPositionCompiles do
      def sum_above(list, cutoff) do
        Enum.reduce(list, 0, fn
          {key, val} when key > cutoff, acc -> acc + val
          _, acc -> acc
        end)
      end
    end
    """

    assert compiles?(fix(input))
  end

  test "end-to-end: the semantic phase dispatches this rule on the real diagnostic" do
    input = """
    defmodule CredenceFnGuardPositionE2E do
      def sum_above(list, cutoff) do
        Enum.reduce(list, 0, fn
          {key, val} when key > cutoff, acc -> acc + val
          _, acc -> acc
        end)
      end
    end
    """

    expected = """
    defmodule CredenceFnGuardPositionE2E do
      def sum_above(list, cutoff) do
        Enum.reduce(list, 0, fn
          {key, val}, acc when key > cutoff -> acc + val
          _, acc -> acc
        end)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "leaves a clause with two misplaced whens unchanged (deliberately skipped)" do
    input = """
    defmodule M do
      def make do
        fn a when is_integer(a), b when is_integer(b) -> a + b end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves a misplaced when in a def head unchanged (fix only touches fn)" do
    input = """
    defmodule M do
      def f(x when is_atom(x), y), do: {x, y}
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def sum_above(list, cutoff) do
        Enum.reduce(list, 0, fn
          {key, val} when key > cutoff, acc -> acc + val
          _, acc -> acc
        end)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when when is correctly placed" do
    input = """
    defmodule M do
      def sum_above(list, cutoff) do
        Enum.reduce(list, 0, fn
          {key, val}, acc when key > cutoff -> acc + val
          _, acc -> acc
        end)
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged for fn without guard" do
    input = """
    defmodule M do
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input), input)
  end
end
