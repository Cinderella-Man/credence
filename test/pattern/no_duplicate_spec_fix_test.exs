defmodule Credence.Pattern.NoDuplicateSpecFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDuplicateSpec

  test "removes duplicate @spec before multi-clause function" do
    input = """
    defmodule Solution do
      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(0), do: 0

      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(number) when is_integer(number) and number >= 0 do
        root = floor(:math.sqrt(number))
        root * root
      end
    end
    """

    expected = """
    defmodule Solution do
      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(0), do: 0

      def largest_square_number(number) when is_integer(number) and number >= 0 do
        root = floor(:math.sqrt(number))
        root * root
      end
    end
    """

    assert fix(NoDuplicateSpec, input) == expected
  end

  test "removes multiple duplicate @spec annotations" do
    input = """
    defmodule Solution do
      @spec foo(integer()) :: integer()
      def foo(0), do: 0

      @spec foo(integer()) :: integer()
      def foo(n), do: n

      @spec foo(integer()) :: integer()
      def foo(n) when n > 0, do: n + 1
    end
    """

    expected = """
    defmodule Solution do
      @spec foo(integer()) :: integer()
      def foo(0), do: 0

      def foo(n), do: n

      def foo(n) when n > 0, do: n + 1
    end
    """

    assert fix(NoDuplicateSpec, input) == expected
  end

  test "leaves code with single @spec unchanged" do
    code = """
    defmodule Good do
      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(0), do: 0

      def largest_square_number(number) when is_integer(number) and number >= 0 do
        root = floor(:math.sqrt(number))
        root * root
      end
    end
    """

    assert fix(NoDuplicateSpec, code) == code
  end

  test "leaves @spec for different functions unchanged" do
    code = """
    defmodule Good do
      @spec add(integer(), integer()) :: integer()
      def add(a, b), do: a + b

      @spec sub(integer(), integer()) :: integer()
      def sub(a, b), do: a - b
    end
    """

    assert fix(NoDuplicateSpec, code) == code
  end
end
