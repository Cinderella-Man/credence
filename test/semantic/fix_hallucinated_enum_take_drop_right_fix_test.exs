defmodule Credence.Semantic.FixHallucinatedEnumTakeDropRightFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedEnumTakeDropRight

  @take_message "Enum.take_right/2 is undefined or private"
  @drop_message "Enum.drop_right/2 is undefined or private"

  defp fix(source, message, line \\ 1) do
    FixHallucinatedEnumTakeDropRight.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces Enum.take_right with Enum.take and negated count" do
    input = """
    defmodule HallucinatedEnumRight do
      def take_from_right(list, n) do
        Enum.take_right(list, n)
      end
    end
    """

    expected = """
    defmodule HallucinatedEnumRight do
      def take_from_right(list, n) do
        Enum.take(list, -n)
      end
    end
    """

    confirm_fix(fix(input, @take_message, 3), expected)
  end

  test "replaces Enum.drop_right with Enum.drop and negated count" do
    input = """
    defmodule HallucinatedEnumRight do
      def drop_from_right(list, n) do
        Enum.drop_right(list, n)
      end
    end
    """

    expected = """
    defmodule HallucinatedEnumRight do
      def drop_from_right(list, n) do
        Enum.drop(list, -n)
      end
    end
    """

    confirm_fix(fix(input, @drop_message, 3), expected)
  end

  test "fixes both take_right and drop_right in the same module" do
    input = """
    defmodule HallucinatedEnumRight do
      def take_from_right(list, n) do
        Enum.take_right(list, n)
      end

      def drop_from_right(list, n) do
        Enum.drop_right(list, n)
      end
    end
    """

    expected = """
    defmodule HallucinatedEnumRight do
      def take_from_right(list, n) do
        Enum.take(list, -n)
      end

      def drop_from_right(list, n) do
        Enum.drop(list, -n)
      end
    end
    """

    confirm_fix(fix(input, @take_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def example(list) do
        Enum.take_right(list, 3)
      end
    end
    """

    assert valid_syntax?(fix(input, @take_message, 3))
  end

  test "returns source unchanged when no hallucinated function present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @take_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input, @take_message), input)
  end
end
