defmodule Credence.Syntax.PreferFnEndSyntaxAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferFnEndSyntax

  defp analyze(code), do: PreferFnEndSyntax.analyze(code)

  describe "flags bare arrow syntax" do
    test "single parameter lambda" do
      assert [%Issue{rule: :prefer_fn_end_syntax}] =
               analyze("""
               Enum.reduce(1..n, 1, acc -> acc * n)
               """)
    end

    test "multi-parameter lambda" do
      assert [%Issue{rule: :prefer_fn_end_syntax}] =
               analyze("""
               Enum.reduce(list, 0, x, acc -> x + acc)
               """)
    end

    test "bare arrow in assignment" do
      assert [%Issue{rule: :prefer_fn_end_syntax}] =
               analyze("""
               f = x -> x + 1
               """)
    end
  end

  describe "leaves valid code alone" do
    test "fn ... end syntax" do
      assert analyze("""
             Enum.reduce(1..n, 1, fn acc, _i -> acc * n end)
             """) == []
    end

    test "case expression" do
      assert analyze("""
             case x do y -> y end
             """) == []
    end

    test "cond expression" do
      assert analyze("""
             cond do
               value > 3 -> :big
               true -> :small
             end
             """) == []
    end

    test "no arrow at all" do
      assert analyze("""
             x + 1
             """) == []
    end
  end
end
