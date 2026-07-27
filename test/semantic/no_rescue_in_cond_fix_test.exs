defmodule Credence.Semantic.NoRescueInCondFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRescueInCond

  @message_rescue "unexpected option :rescue in \"cond\""
  @message_catch "unexpected option :catch in \"cond\""

  defp fix(source, message, line \\ 1) do
    NoRescueInCond.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "wraps cond-rescue in try" do
    input = ~S"""
    defmodule BadRescueInCond do
      def run do
        cond do
          true -> :ok
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    expected = ~S"""
    defmodule BadRescueInCond do
      def run do
        try do
          cond do
            true -> :ok
          end
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), expected)
  end

  test "wraps cond-catch in try" do
    input = ~S"""
    defmodule CondWithCatch do
      def run do
        cond do
          true -> :ok
        catch
          e -> {:error, e}
        end
      end
    end
    """

    expected = ~S"""
    defmodule CondWithCatch do
      def run do
        try do
          cond do
            true -> :ok
          end
        catch
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message_catch), expected)
  end

  test "wraps cond-rescue-catch in try" do
    input = ~S"""
    defmodule CondWithBoth do
      def run do
        cond do
          true -> :ok
        rescue
          e -> {:error, e}
        catch
          e -> {:error, e}
        end
      end
    end
    """

    expected = ~S"""
    defmodule CondWithBoth do
      def run do
        try do
          cond do
            true -> :ok
          end
        rescue
          e -> {:error, e}
        catch
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule ParseCheck do
      def check do
        cond do
          true -> :ok
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message_rescue))
  end

  test "returns source unchanged when cond has no rescue or catch" do
    input = ~S"""
    defmodule NormalCond do
      def check(x) do
        cond do
          x > 0 -> :positive
          x < 0 -> :negative
          true -> :zero
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), input)
  end
end
