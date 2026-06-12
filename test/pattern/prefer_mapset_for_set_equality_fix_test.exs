defmodule Credence.Pattern.PreferMapsetForSetEqualityFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapsetForSetEquality

  test "rewrites the anti-pattern" do
    input = """
    defmodule Solution do
      def same_char_sets?(first, second) do
        first_set = String.codepoints(first) |> Enum.uniq() |> Enum.sort()
        second_set = String.codepoints(second) |> Enum.uniq() |> Enum.sort()
        first_set == second_set
      end
    end
    """

    expected = """
    defmodule Solution do
      def same_char_sets?(first, second) do
        MapSet.new(String.codepoints(first)) == MapSet.new(String.codepoints(second))
      end
    end
    """

    assert fix(PreferMapsetForSetEquality, input) == expected
  end
end
