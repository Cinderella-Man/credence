defmodule Credence.Semantic.PreferTlOverEnumTailFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferTlOverEnumTail

  @real_message "Enum.tail/1 is undefined or private"

  defp fix(source, line) do
    PreferTlOverEnumTail.fix(source, %{severity: :warning, message: @real_message, position: {line, 1}})
  end

  test "fixes Enum.tail(chars) to tl(chars)" do
    input = """
    defmodule Solution do
      def sub_count(text, substr) do
        do_count(String.graphemes(text), substr, 0)
      end

      defp do_count([], _substr, acc), do: acc

      defp do_count(chars, substr, acc) do
        remaining = Enum.join(chars)
        count = count_in(remaining, substr)
        do_count(Enum.tail(chars), substr, acc + count)
      end
    end
    """

    expected = """
    defmodule Solution do
      def sub_count(text, substr) do
        do_count(String.graphemes(text), substr, 0)
      end

      defp do_count([], _substr, acc), do: acc

      defp do_count(chars, substr, acc) do
        remaining = Enum.join(chars)
        count = count_in(remaining, substr)
        do_count(tl(chars), substr, acc + count)
      end
    end
    """

    confirm_fix(fix(input, 11), expected)
  end

  test "only rewrites the flagged line" do
    input = """
    defmodule Solution do
      def a(list), do: Enum.tail(list)
      def b(list), do: Enum.tail(list)
    end
    """

    expected = """
    defmodule Solution do
      def a(list), do: tl(list)
      def b(list), do: Enum.tail(list)
    end
    """

    confirm_fix(fix(input, 2), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Solution do
      def head(list), do: Enum.tail(list)
    end
    """

    assert valid_syntax?(fix(input, 2))
  end
end
