defmodule Credence.Syntax.NoOutputMarkerLinesAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoOutputMarkerLines

  defp analyze(code), do: NoOutputMarkerLines.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_output_marker_lines}] =
             analyze("""
             ---MODULE---
             defmodule Solution do
               @doc "Greets the world."
               def hello, do: :world
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Solution do
             @doc "Greets the world."
             def hello, do: :world
           end
           """) == []
  end
end
