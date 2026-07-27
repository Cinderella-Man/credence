defmodule Credence.Semantic.NoEnumSortThenMapValuesFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoEnumSortThenMapValues

  @real_message "the result of evaluating operator '+'/2 is ignored (suppress the warning by assigning the expression to the _ variable)"

  defp fix(source, message, line \\ 1) do
    NoEnumSortThenMapValues.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces Map.values() with Enum.map after sort_by" do
    input = """
    defmodule Example do
      def oldest_first(payments) do
        payments
        |> Enum.sort_by(fn {id, _} ->
          String.to_integer(String.replace_prefix(id, "pay_", ""))
        end)
        |> Map.values()
      end
    end
    """

    expected = """
    defmodule Example do
      def oldest_first(payments) do
        payments
        |> Enum.sort_by(fn {id, _} ->
          String.to_integer(String.replace_prefix(id, "pay_", ""))
        end)
        |> Enum.map(fn {_, v} -> v end)
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def oldest_first(payments) do
        payments
        |> Enum.sort_by(fn {id, _} ->
          String.to_integer(String.replace_prefix(id, "pay_", ""))
        end)
        |> Map.values()
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no Map.values() pipe" do
    input = """
    defmodule Clean do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged when Map.values() is not after sort_by" do
    input = """
    defmodule DirectCall do
      def values(map) do
        Map.values(map)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
