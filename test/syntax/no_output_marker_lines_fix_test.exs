defmodule Credence.Syntax.NoOutputMarkerLinesFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoOutputMarkerLines

  defp analyze(code), do: NoOutputMarkerLines.analyze(code)
  defp fix(code), do: NoOutputMarkerLines.fix(code)

  test "fixes the syntax error" do
    input = """
    ---MODULE---
    defmodule Solution do
      @doc "Greets the world."
      def hello, do: :world
    end
    """

    expected = """
    defmodule Solution do
      @doc "Greets the world."
      def hello, do: :world
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             ---MODULE---
             defmodule Solution do
               @doc "Greets the world."
               def hello, do: :world
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             ---MODULE---
             defmodule Solution do
               @doc "Greets the world."
               def hello, do: :world
             end
             """)
           )
  end
end
