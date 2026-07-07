defmodule Credence.Semantic.NoIfAssignmentAsStatementFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoIfAssignmentAsStatement

  @message "undefined variable \"cost\""

  defp fix(source, message, line \\ 1) do
    NoIfAssignmentAsStatement.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "restructures if/else assignment to expression-position assignment" do
    input = ~S"""
    defmodule Mod do
      def example(list) do
        Enum.reduce(list, 0, fn item, acc ->
          if item > 0 do
            cost = 1
          else
            cost = 2
          end

          acc + cost
        end)
      end
    end
    """

    expected = ~S"""
    defmodule Mod do
      def example(list) do
        Enum.reduce(list, 0, fn item, acc ->
          cost =
            if item > 0,
              do: 1,
              else: 2

          acc + cost
        end)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixes a simple if/else assignment" do
    input = ~S"""
    defmodule Simple do
      def pick(x) do
        if x > 10 do
          result = :big
        else
          result = :small
        end

        result
      end
    end
    """

    expected = ~S"""
    defmodule Simple do
      def pick(x) do
        result =
          if x > 10,
            do: :big,
            else: :small

        result
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"result\""), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule ParseCheck do
      def check(x) do
        if x > 0 do
          cost = 1
        else
          cost = 2
        end

        cost
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no if/else assignment pattern" do
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

  test "returns source unchanged when branches assign different variables" do
    input = ~S"""
    defmodule DifferentVars do
      def check(x) do
        if x > 0 do
          a = 1
        else
          b = 2
        end

        a + b
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"a\""), input)
  end
end
