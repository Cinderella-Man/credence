defmodule Credence.Pattern.PreferPatternMatchOverIfEmptyListFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPatternMatchOverIfEmptyList

  test "rewrites the anti-pattern" do
    input = """
    defmodule Solution do
      @spec process(list()) :: non_neg_integer()
      def process(list) do
        if list == [] do
          0
        else
          Enum.sum(list)
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      @spec process(list()) :: non_neg_integer()
      def process([]), do: 0

      def process(list) do
        Enum.sum(list)
      end
    end
    """

    assert fix(PreferPatternMatchOverIfEmptyList, input) == expected
  end

  test "rewrites reversed condition: [] == list" do
    input = """
    defmodule M do
      def process(list) do
        if [] == list do
          0
        else
          Enum.sum(list)
        end
      end
    end
    """

    expected = """
    defmodule M do
      def process([]), do: 0

      def process(list) do
        Enum.sum(list)
      end
    end
    """

    assert fix(PreferPatternMatchOverIfEmptyList, input) == expected
  end

  test "does not modify clean code" do
    code = """
    defmodule M do
      def process(list) do
        Enum.sum(list)
      end
    end
    """

    assert fix(PreferPatternMatchOverIfEmptyList, code) == code
  end

  test "round-trip: fixed code produces no issues" do
    code = """
    defmodule M do
      def process(list) do
        if list == [] do
          0
        else
          Enum.sum(list)
        end
      end
    end
    """

    assert check(PreferPatternMatchOverIfEmptyList, fix(PreferPatternMatchOverIfEmptyList, code)) == []
  end

  test "rewrites guarded if Enum.empty?(list), preserving the is_list guard on fall-through" do
    code = """
    defmodule M do
      def total(list) when is_list(list) do
        if Enum.empty?(list) do
          :none
        else
          Enum.sum(list)
        end
      end
    end
    """

    expected = """
    defmodule M do
      def total([]), do: :none

      def total(list) when is_list(list) do
        Enum.sum(list)
      end
    end
    """

    assert fix(PreferPatternMatchOverIfEmptyList, code) == expected
  end
end
