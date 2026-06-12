defmodule Credence.Pattern.PreferMapsetForSetEqualityCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapsetForSetEquality

  test "flags the anti-pattern" do
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

  test "leaves good code alone" do
    assert clean?(PreferMapsetForSetEquality, """
           defmodule Solution do
             def same_char_sets?(first, second) do
               MapSet.new(String.codepoints(first)) == MapSet.new(String.codepoints(second))
             end
           end
           """)
  end
end
