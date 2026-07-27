defmodule Credence.Syntax.FixKeywordBlockAsFunctionArgAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixKeywordBlockAsFunctionArg

  defp analyze(code), do: FixKeywordBlockAsFunctionArg.analyze(code)

  test "flags the unparseable code" do
    code = """
    defmodule M do
      def sort(list, desc?) do
        Enum.sort_by(list, & &1, if desc?, do: :desc, else: :asc)
      end
    end
    """

    assert [%Issue{rule: :fix_keyword_block_as_function_arg, meta: %{line: 3}}] = analyze(code)
  end

  test "leaves good code alone" do
    code = """
    defmodule M do
      def sort(list, desc?) do
        Enum.sort_by(list, & &1, (if desc?, do: :desc, else: :asc))
      end
    end
    """

    assert analyze(code) == []
  end
end
