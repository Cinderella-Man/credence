defmodule Credence.Syntax.PreferCondDoKeywordFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.PreferCondDoKeyword

  defp analyze(code), do: PreferCondDoKeyword.analyze(code)
  defp fix(code), do: PreferCondDoKeyword.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Solution do
      def find_min(list) do
        cond ->
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      def find_min(list) do
        cond do
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               def find_min(list) do
                 cond ->
                   list == [] -> nil
                   true -> Enum.min(list)
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
               def find_min(list) do
                 cond ->
                   list == [] -> nil
                   true -> Enum.min(list)
                 end
               end
             end
             """)
           )
  end
end
