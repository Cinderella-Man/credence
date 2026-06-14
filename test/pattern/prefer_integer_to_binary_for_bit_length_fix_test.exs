defmodule Credence.Pattern.PreferIntegerToBinaryForBitLengthFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferIntegerToBinaryForBitLength

  test "rewrites the anti-pattern" do
    input = """
    defmodule Solution do
      def num_of_bits(0), do: 0

      def num_of_bits(n) when n > 0 do
        floor(:math.log(n) / :math.log(2)) + 1
      end
    end
    """

    expected = """
    defmodule Solution do
      def num_of_bits(0), do: 0

      def num_of_bits(n) when n > 0 do
        n
        |> :erlang.integer_to_binary(2)
        |> String.length()
      end

      def num_of_bits(n) when n < 0, do: num_of_bits(-n)
    end
    """

    confirm_fix(fix(PreferIntegerToBinaryForBitLength, input), expected)
  end

  test "rewrites with doc and spec" do
    input = ~S'''
    defmodule Solution do
      @doc """
      Returns the number of bits required to represent a non-negative integer.
      For 0, returns 0.
      """
      @spec num_of_bits(non_neg_integer()) :: non_neg_integer()
      def num_of_bits(0), do: 0

      def num_of_bits(n) when n > 0 do
        floor(:math.log(n) / :math.log(2)) + 1
      end
    end
    '''

    expected = ~S'''
    defmodule Solution do
      @doc """
      Returns the number of bits required to represent a non-negative integer.
      For 0, returns 0.
      """
      @spec num_of_bits(non_neg_integer()) :: non_neg_integer()
      def num_of_bits(0), do: 0

      def num_of_bits(n) when n > 0 do
        n
        |> :erlang.integer_to_binary(2)
        |> String.length()
      end

      def num_of_bits(n) when n < 0, do: num_of_bits(-n)
    end
    '''

    confirm_fix(fix(PreferIntegerToBinaryForBitLength, input), expected)
  end

  test "does not touch clean code" do
    code = """
    defmodule Solution do
      def num_of_bits(0), do: 0

      def num_of_bits(n) when n > 0 do
        n
        |> :erlang.integer_to_binary(2)
        |> String.length()
      end
    end
    """

    confirm_fix(fix(PreferIntegerToBinaryForBitLength, code), code)
  end

  test "rewrites with different variable name" do
    input = """
    defmodule Helper do
      def bits(x) when x > 0 do
        floor(:math.log(x) / :math.log(2)) + 1
      end
    end
    """

    expected = """
    defmodule Helper do
      def bits(x) when x > 0 do
        x
        |> :erlang.integer_to_binary(2)
        |> String.length()
      end

      def bits(x) when x < 0, do: bits(-x)
    end
    """

    confirm_fix(fix(PreferIntegerToBinaryForBitLength, input), expected)
  end
end
