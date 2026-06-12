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

  # Regression (row 101389): an indented marker was not stripped by the old
  # `^---[A-Z_]+---$` anchor (it required the marker at column 1). The `\\s*`-
  # tolerant pattern also covers trailing whitespace and a trailing CR (CRLF),
  # which can't be expressed in a heredoc fixture but are exercised in iex.
  test "strips an indented marker line" do
    input = """
    defmodule T do
    end

      ---TEST---
    ---END---
    """

    fixed = fix(input)
    refute String.contains?(fixed, "---")
    assert valid_syntax?(fixed)
  end

  test "leaves real code containing a hyphen untouched" do
    input = """
    x = a - b
    """

    assert fix(input) == input
  end
end
