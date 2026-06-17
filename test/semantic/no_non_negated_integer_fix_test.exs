defmodule Credence.Semantic.NoNonNegatedIntegerFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoNonNegatedInteger

  @message "credence_check.ex:5: type non_negated_integer/0 undefined (no such type in Solution)"

  defp fix(source, message \\ @message, line \\ 2) do
    NoNonNegatedInteger.fix(source, %{severity: :error, message: message, position: line})
  end

  test "fixes the source" do
    input = """
    defmodule Solution do
      @spec power_of_num(number(), non_negated_integer()) :: number()
      def power_of_num(_base, 0) do
        1
      end

      def power_of_num(base, exponent) when is_integer(exponent) and exponent > 0 do
        base * power_of_num(base, exponent - 1)
      end
    end
    """

    expected = """
    defmodule Solution do
      @spec power_of_num(number(), non_neg_integer()) :: number()
      def power_of_num(_base, 0) do
        1
      end

      def power_of_num(base, exponent) when is_integer(exponent) and exponent > 0 do
        base * power_of_num(base, exponent - 1)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Solution do
      @spec power_of_num(number(), non_negated_integer()) :: number()
      def power_of_num(_base, 0) do
        1
      end

      def power_of_num(base, exponent) when is_integer(exponent) and exponent > 0 do
        base * power_of_num(base, exponent - 1)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "handles multiple occurrences in a single fix" do
    input = """
    defmodule Solution do
      @spec foo(non_negated_integer()) :: non_negated_integer()
      def foo(x), do: x
    end
    """

    expected = """
    defmodule Solution do
      @spec foo(non_neg_integer()) :: non_neg_integer()
      def foo(x), do: x
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "only rewrites the flagged line, leaving same-named string literals intact" do
    input = """
    defmodule M do
      @spec f(non_negated_integer()) :: String.t()
      def f(_x), do: "non_negated_integer"
    end
    """

    expected = """
    defmodule M do
      @spec f(non_neg_integer()) :: String.t()
      def f(_x), do: "non_negated_integer"
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "returns source unchanged when no non_negated_integer present" do
    input = """
    defmodule Solution do
      @spec foo(non_neg_integer()) :: non_neg_integer()
      def foo(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end
end
