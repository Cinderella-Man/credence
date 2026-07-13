defmodule Credence.Semantic.FixMapFetchNoneClauseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixMapFetchNoneClause

  @message "an expression is always required on the right side of ->. Please provide a value after ->"

  defp fix(source, message, line \\ 1) do
    FixMapFetchNoneClause.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces :none with :error in Map.fetch case clause" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    expected = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :error -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no Map.fetch case" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.get(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "does not touch :none in non-Map.fetch case" do
    input = ~S"""
    defmodule Example do
      def classify(status) do
        case status do
          :none -> :empty
          :some -> :present
        end
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
