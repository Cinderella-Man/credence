defmodule Credence.Semantic.NoCondVariableAssignmentInInnerBranchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoCondVariableAssignmentInInnerBranch

  @message "undefined variable \"count\""

  defp fix(source, message, line \\ 1) do
    NoCondVariableAssignmentInInnerBranch.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "hoists branch assignment before if/else" do
    input = ~S"""
    defmodule Example do
      def count_above(list, threshold) do
        Enum.each(list, fn x ->
          if x > threshold do
            count = 1
          else
            count = 0
          end

          count
        end)
      end
    end
    """

    expected = ~S"""
    defmodule Example do
      def count_above(list, threshold) do
        Enum.each(list, fn x ->
          count =
            if x > threshold do
              1
            else
              0
            end

          count
        end)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixes if/else with atom values" do
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
          if x > 10 do
            :big
          else
            :small
          end

        result
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"result\""), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule Example do
      def count_above(list, threshold) do
        Enum.each(list, fn x ->
          if x > threshold do
            count = 1
          else
            count = 0
          end

          count
        end)
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no if/else branch assignment pattern" do
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

  test "returns source unchanged when only one branch assigns" do
    input = ~S"""
    defmodule OneBranch do
      def check(x) do
        if x > 0 do
          count = 1
        else
          0
        end

        count
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
