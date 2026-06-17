defmodule Credence.Pattern.PreferMapsetForSetEqualityFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapsetForSetEquality

  test "rewrites the anti-pattern (codepoints)" do
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

    confirm_fix(fix(PreferMapsetForSetEquality, input), expected)
  end

  test "rewrites the anti-pattern (graphemes)" do
    input = """
    defmodule Solution do
      def same_char_sets?(first, second) do
        a = String.graphemes(first) |> Enum.uniq() |> Enum.sort()
        b = String.graphemes(second) |> Enum.uniq() |> Enum.sort()
        a == b
      end
    end
    """

    expected = """
    defmodule Solution do
      def same_char_sets?(first, second) do
        MapSet.new(String.graphemes(first)) == MapSet.new(String.graphemes(second))
      end
    end
    """

    confirm_fix(fix(PreferMapsetForSetEquality, input), expected)
  end

  test "does not touch a non-String inner call" do
    input = """
    defmodule Solution do
      def same_sets?(first, second) do
        a = Map.values(first) |> Enum.uniq() |> Enum.sort()
        b = Map.values(second) |> Enum.uniq() |> Enum.sort()
        a == b
      end
    end
    """

    confirm_fix(fix(PreferMapsetForSetEquality, input), input)
  end

  test "does not touch a block with extra statements" do
    input = """
    defmodule Solution do
      def same_char_sets?(first, second) do
        a = String.codepoints(first) |> Enum.uniq() |> Enum.sort()
        b = String.codepoints(second) |> Enum.uniq() |> Enum.sort()
        IO.inspect(a)
        a == b
      end
    end
    """

    confirm_fix(fix(PreferMapsetForSetEquality, input), input)
  end
end
