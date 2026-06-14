defmodule Credence.Syntax.CloseUnclosedFnDelimiterFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.CloseUnclosedFnDelimiter

  defp analyze(code), do: CloseUnclosedFnDelimiter.analyze(code)
  defp fix(code), do: CloseUnclosedFnDelimiter.fix(code)

  test "inserts missing end before ) and removes stray end on next line" do
    input = """
    defmodule Solution do
      def replace_zero(matrix) do
        Enum.map(matrix, fn row ->
          non_zeros = Enum.filter(row, fn element -> element != 0 end)
          case non_zeros do
            [] -> row
            _ ->
              min_value = Enum.min(non_zeros)
              Enum.map(row, fn element ->
                if element == 0 do min_value else element end)
              end
          end
        end)
      end
    end
    """

    expected = """
    defmodule Solution do
      def replace_zero(matrix) do
        Enum.map(matrix, fn row ->
          non_zeros = Enum.filter(row, fn element -> element != 0 end)
          case non_zeros do
            [] -> row
            _ ->
              min_value = Enum.min(non_zeros)
              Enum.map(row, fn element ->
                if element == 0 do min_value else element end end)
          end
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = """
    defmodule Solution do
      def replace_zero(matrix) do
        Enum.map(matrix, fn row ->
          non_zeros = Enum.filter(row, fn element -> element != 0 end)
          case non_zeros do
            [] -> row
            _ ->
              min_value = Enum.min(non_zeros)
              Enum.map(row, fn element ->
                if element == 0 do min_value else element end)
              end
          end
        end)
      end
    end
    """

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = """
    defmodule Solution do
      def replace_zero(matrix) do
        Enum.map(matrix, fn row ->
          non_zeros = Enum.filter(row, fn element -> element != 0 end)
          case non_zeros do
            [] -> row
            _ ->
              min_value = Enum.min(non_zeros)
              Enum.map(row, fn element ->
                if element == 0 do min_value else element end)
              end
          end
        end)
      end
    end
    """

    assert valid_syntax?(fix(code))
  end

  test "does not modify already-valid code" do
    code = "Enum.map(list, fn x -> x end)"

    confirm_fix(fix(code), code)
  end
end
