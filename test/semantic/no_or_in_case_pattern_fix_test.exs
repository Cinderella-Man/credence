defmodule Credence.Semantic.NoOrInCasePatternFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoOrInCasePattern

  @msg "or is not allowed in patterns"

  defp fix(source, line \\ 1) do
    NoOrInCasePattern.fix(source, %{severity: :error, message: @msg, position: {line, 1}})
  end

  test "splits or pattern into separate clauses" do
    input = """
    defmodule Example do
      def classify(value) do
        case value do
          nil or "" -> :empty
          _ -> :present
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def classify(value) do
        case value do
          nil -> :empty
          "" -> :empty
          _ -> :present
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def classify(value) do
        case value do
          nil or "" -> :empty
          _ -> :present
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "end-to-end: the semantic pipeline resolves the real compile error" do
    input = """
    defmodule Example do
      def classify(value) do
        case value do
          nil or "" -> :empty
          _ -> :present
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def classify(value) do
        case value do
          nil -> :empty
          "" -> :empty
          _ -> :present
        end
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end
end
