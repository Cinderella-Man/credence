defmodule Credence.Pattern.PreferTupleForRandomAccessCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferTupleForRandomAccess

  test "flags Enum.fetch! inside a for comprehension" do
    assert flagged?(PreferTupleForRandomAccess, """
           for i <- 0..3, do: Enum.fetch!(list, i)
           """)
  end

  test "flags Enum.fetch! in for comprehension filter" do
    assert flagged?(PreferTupleForRandomAccess, """
           for i <- 0..3,
               Enum.fetch!(list, i) > 2,
               do: i
           """)
  end

  test "flags Enum.fetch! in for comprehension with multiple generators" do
    assert flagged?(PreferTupleForRandomAccess, """
           n = length(numbers)
           for i <- 0..(n - 2),
               j <- (i + 1)..(n - 1),
               abs(Enum.fetch!(numbers, i) - Enum.fetch!(numbers, j)) == k,
               do: {i, j}
           """)
  end

  test "leaves code without Enum.fetch! alone" do
    assert clean?(PreferTupleForRandomAccess, """
           for i <- 0..3, do: Enum.at(list, i)
           """)
  end

  test "leaves Enum.fetch! outside a for comprehension alone" do
    assert clean?(PreferTupleForRandomAccess, """
           Enum.fetch!(list, 0)
           """)
  end

  test "leaves non-for Enum.fetch! alone" do
    assert clean?(PreferTupleForRandomAccess, """
           x = Enum.fetch!(list, 0)
           IO.puts(x)
           """)
  end
end
