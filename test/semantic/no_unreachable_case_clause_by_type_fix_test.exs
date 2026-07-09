defmodule Credence.Semantic.NoUnreachableCaseClauseByTypeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnreachableCaseClauseByType

  @message "the following clause will never match:\n\n    :dt\n\nbecause it attempts to match on the result of:\n\n    DateTime.compare(due1, due2)\n\nwhich has type:\n\n    dynamic(:eq or :gt or :lt)\n"

  defp fix(source, message \\ @message, line \\ 1) do
    NoUnreachableCaseClauseByType.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "removes the unreachable :dt clause" do
    input = """
    defmodule Example do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
          :dt -> :unknown
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
          :dt -> :unknown
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no matching atom in case" do
    input = """
    defmodule Example do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when message does not contain an atom" do
    input = """
    defmodule Example do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
          :dt -> :unknown
        end
      end
    end
    """

    bad_message = "the following clause will never match:\n\n    something weird\n\nbecause it attempts to match on the result of:\n\n    foo\n\nwhich has type:\n\n    bar\n"
    confirm_fix(fix(input, bad_message), input)
  end
end
