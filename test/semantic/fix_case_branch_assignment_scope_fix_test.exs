defmodule Credence.Semantic.FixCaseBranchAssignmentScopeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixCaseBranchAssignmentScope

  @message "undefined variable \"label\""

  defp fix(source, message, line \\ 1) do
    FixCaseBranchAssignmentScope.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes case branch assignment hoisting" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> label = "success"
          :error -> label = "failure"
          _ -> label = "unknown"
        end

        String.upcase(label)
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def classify(x) do
        label =
          case x do
            :ok -> "success"
            :error -> "failure"
            _ -> "unknown"
          end

        String.upcase(label)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixes case with two branches" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> result = 1
          :error -> result = 2
        end

        result + 10
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def classify(x) do
        result =
          case x do
            :ok -> 1
            :error -> 2
          end

        result + 10
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"result\""), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> label = "success"
          :error -> label = "failure"
          _ -> label = "unknown"
        end

        String.upcase(label)
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no case branch assignment pattern" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        label = to_string(x)
        String.upcase(label)
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "returns source unchanged when variable is not used after case" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> label = "success"
          :error -> label = "failure"
        end

        :ok
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"label\""), input)
  end
end
