defmodule Credence.Semantic.FixHallucinatedEnumRangeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedEnumRange

  @message "Enum.range/2 is undefined or private"

  defp fix(source, message, line \\ 1) do
    FixHallucinatedEnumRange.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces Enum.range with range literal" do
    input = """
    defmodule HallucinatedEnumRange do
      def example(list) do
        Enum.reduce_while(
          Enum.range(0, length(list) - 1),
          :ok,
          fn i, _acc ->
            if i > 5, do: {:halt, :done}, else: {:cont, :ok}
          end
        )
      end
    end
    """

    expected = """
    defmodule HallucinatedEnumRange do
      def example(list) do
        Enum.reduce_while(
          0..(length(list) - 1),
          :ok,
          fn i, _acc ->
            if i > 5, do: {:halt, :done}, else: {:cont, :ok}
          end
        )
      end
    end
    """

    confirm_fix(fix(input, @message, 4), expected)
  end

  test "fixes simple Enum.range(a, b) to a..b" do
    input = """
    defmodule M do
      def example do
        Enum.range(1, 10)
      end
    end
    """

    expected = """
    defmodule M do
      def example do
        1..10
      end
    end
    """

    confirm_fix(fix(input, @message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def example(list) do
        Enum.range(0, length(list) - 1)
      end
    end
    """

    assert valid_syntax?(fix(input, @message, 3))
  end

  test "returns source unchanged when no Enum.range present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
