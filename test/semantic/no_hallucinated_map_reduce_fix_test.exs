defmodule Credence.Semantic.NoHallucinatedMapReduceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedMapReduce

  @message "Map.reduce/3 is undefined or private"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedMapReduce.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces Map.reduce with Enum.reduce and tuple-destructures the callback" do
    input = """
    defmodule M do
      def process(map) do
        Map.reduce(map, %{}, fn key, value, acc ->
          Map.put(acc, key, value)
        end)
      end
    end
    """

    expected = """
    defmodule M do
      def process(map) do
        Enum.reduce(map, %{}, fn {key, value}, acc ->
          Map.put(acc, key, value)
        end)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def process(map) do
        Map.reduce(map, %{}, fn key, value, acc ->
          Map.put(acc, key, value)
        end)
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no Map.reduce present" do
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
