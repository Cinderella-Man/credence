defmodule Credence.Syntax.FixKeywordBlockAsFunctionArgFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixKeywordBlockAsFunctionArg

  defp analyze(code), do: FixKeywordBlockAsFunctionArg.analyze(code)
  defp fix(code), do: FixKeywordBlockAsFunctionArg.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule M do
      def sort(list, desc?) do
        Enum.sort_by(list, & &1, if desc?, do: :desc, else: :asc)
      end
    end
    """

    expected = """
    defmodule M do
      def sort(list, desc?) do
        Enum.sort_by(list, & &1, (if desc?, do: :desc, else: :asc))
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule M do
      def sort(list, desc?) do
        Enum.sort_by(list, & &1, if desc?, do: :desc, else: :asc)
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def sort(list, desc?) do
        Enum.sort_by(list, & &1, if desc?, do: :desc, else: :asc)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
