defmodule Credence.Syntax.NoEndKeywordVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoEndKeywordVariable

  defp analyze(code), do: NoEndKeywordVariable.analyze(code)
  defp fix(code), do: NoEndKeywordVariable.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Solution do
      def calc(a, b) do
        end = a + b
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      def calc(a, b) do
        result = a + b
        result
      end
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               def calc(a, b) do
                 end = a + b
                 end
               end
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               def calc(a, b) do
                 end = a + b
                 end
               end
             end
             """)
           )
  end
end
