defmodule Credence.Pattern.PreferMapsetForSetEqualityCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapsetForSetEquality

  test "flags the anti-pattern with String.codepoints" do
    assert flagged?(PreferMapsetForSetEquality, """
           defmodule Solution do
             def same_char_sets?(first, second) do
               first_set = String.codepoints(first) |> Enum.uniq() |> Enum.sort()
               second_set = String.codepoints(second) |> Enum.uniq() |> Enum.sort()
               first_set == second_set
             end
           end
           """)
  end

  test "flags the anti-pattern with String.graphemes" do
    assert flagged?(PreferMapsetForSetEquality, """
           defmodule Solution do
             def same_char_sets?(first, second) do
               a = String.graphemes(first) |> Enum.uniq() |> Enum.sort()
               b = String.graphemes(second) |> Enum.uniq() |> Enum.sort()
               a == b
             end
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferMapsetForSetEquality, """
           defmodule Solution do
             def same_char_sets?(first, second) do
               MapSet.new(String.codepoints(first)) == MapSet.new(String.codepoints(second))
             end
           end
           """)
  end

  # No issue: inner call is not a binary-returning String call. List `==`
  # coerces numbers (`[1] == [1.0]` is true) while `MapSet` comparison does
  # not, so this would not be behaviour-preserving.
  test "does not flag a non-String inner call" do
    assert clean?(PreferMapsetForSetEquality, """
           defmodule Solution do
             def same_sets?(first, second) do
               a = Map.values(first) |> Enum.uniq() |> Enum.sort()
               b = Map.values(second) |> Enum.uniq() |> Enum.sort()
               a == b
             end
           end
           """)
  end

  # No issue: the block holds more than the two assignments and their
  # comparison. Collapsing it would drop the extra statement (here a side
  # effect) and break the reference to `a`.
  test "does not flag when the block has extra statements" do
    assert clean?(PreferMapsetForSetEquality, """
           defmodule Solution do
             def same_char_sets?(first, second) do
               a = String.codepoints(first) |> Enum.uniq() |> Enum.sort()
               b = String.codepoints(second) |> Enum.uniq() |> Enum.sort()
               IO.inspect(a)
               a == b
             end
           end
           """)
  end

  # No issue: comparing a variable with itself is not a two-set comparison.
  test "does not flag a self comparison" do
    assert clean?(PreferMapsetForSetEquality, """
           defmodule Solution do
             def degenerate?(first) do
               a = String.codepoints(first) |> Enum.uniq() |> Enum.sort()
               b = String.codepoints(first) |> Enum.uniq() |> Enum.sort()
               a == a
             end
           end
           """)
  end
end
