defmodule Credence.Semantic.FixWithElseBareValueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixWithElseBareValue

  @message ~s(expected -> clauses for :else in "with")

  defp fix(source, message \\ @message, line \\ 1) do
    FixWithElseBareValue.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "wraps bare else value in _ -> expr" do
    input = ~S"""
    defmodule FixWithElseBareValue do
      def check(x) do
        with {:ok, val} <- x do
          val
        else
          :error
        end
      end
    end
    """

    expected = ~S"""
    defmodule FixWithElseBareValue do
      def check(x) do
        with {:ok, val} <- x do
          val
        else
          _ -> :error
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not modify with that already has proper else clauses" do
    input = ~S"""
    defmodule AlreadyCorrect do
      def check(x) do
        with {:ok, val} <- x do
          val
        else
          :error -> :err
          _ -> :unknown
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify with without else" do
    input = ~S"""
    defmodule NoElse do
      def check(x) do
        with {:ok, val} <- x do
          val
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule ParseCheck do
      def check(x) do
        with {:ok, val} <- x do
          val
        else
          :error
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
