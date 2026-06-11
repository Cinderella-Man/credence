defmodule Credence.Pattern.PreferTupleForRandomAccessFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferTupleForRandomAccess

  test "rewrites the anti-pattern" do
    input = """
    defmodule Solution do
      def countpairswithdiffk(numbers, k) do
        n = length(numbers)
        pairs = for i <- 0..(n - 2),
                    j <- (i + 1)..(n - 1),
                    abs(Enum.fetch!(numbers, i) - Enum.fetch!(numbers, j)) == k,
                    do: {i, j}
        Enum.count(pairs)
      end
    end
    """

    expected = """
    defmodule Solution do
      def countpairswithdiffk(numbers, k) do
        numbers_tuple = List.to_tuple(numbers)
        n = tuple_size(numbers_tuple)

        pairs =
          for i <- 0..(n - 2),
              j <- (i + 1)..(n - 1),
              abs(elem(numbers_tuple, i) - elem(numbers_tuple, j)) == k,
              do: {i, j}

        Enum.count(pairs)
      end
    end
    """

    assert fix(PreferTupleForRandomAccess, input) == expected
  end

  test "rewrites standalone for expression" do
    input = """
    for i <- 0..3, do: Enum.fetch!(list, i)
    """

    expected = """
    list_tuple = List.to_tuple(list)
    for i <- 0..3, do: elem(list_tuple, i)
    """

    assert fix(PreferTupleForRandomAccess, input) == expected
  end
end
