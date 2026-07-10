defmodule Credence.Semantic.FixCondBranchAssignmentScopeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixCondBranchAssignmentScope

  @message "undefined variable \"wma1_val\""

  defp fix(source, message, line \\ 1) do
    FixCondBranchAssignmentScope.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes cond with continuation" do
    input = ~S"""
    defmodule M do
      def calc(values) do
        wma1_val =
          cond do
            true ->
              Enum.sum(values)
            false ->
              0
          end

        wma1_val * 2
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def calc(values) do
        wma1_val =
          cond do
            true ->
              Enum.sum(values) * 2

            false ->
              0 * 2
          end
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixes case with continuation" do
    input = ~S"""
    defmodule M do
      def calc(x) do
        result =
          case x do
            :a -> 1
            :b -> 2
          end

        result + 10
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def calc(x) do
        result =
          case x do
            :a -> 1 + 10
            :b -> 2 + 10
          end
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"result\""), expected)
  end

  test "fixes if/else with continuation" do
    input = ~S"""
    defmodule M do
      def calc(x) do
        val =
          if x > 0 do
            x * 2
          else
            0
          end

        val + 1
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def calc(x) do
        val =
          if x > 0 do
            x * 2 + 1
          else
            0 + 1
          end
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"val\""), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule M do
      def calc(values) do
        wma1_val =
          cond do
            true ->
              Enum.sum(values)
            false ->
              0
          end

        wma1_val * 2
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no cond/case/if assignment pattern" do
    input = ~S"""
    defmodule CleanModule do
      def check(x) do
        cost = if x > 0, do: 1, else: 2
        cost
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "returns source unchanged when variable is not used after block" do
    input = ~S"""
    defmodule M do
      def calc(values) do
        wma1_val =
          cond do
            true ->
              Enum.sum(values)
            false ->
              0
          end

        :ok
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
