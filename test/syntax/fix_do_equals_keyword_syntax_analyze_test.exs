defmodule Credence.Syntax.FixDoEqualsKeywordSyntaxAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixDoEqualsKeywordSyntax

  defp analyze(code), do: FixDoEqualsKeywordSyntax.analyze(code)

  describe "flags do = in keyword position" do
    test "in a function definition" do
      assert [%Issue{rule: :fix_do_equals_keyword_syntax}] =
               analyze("""
               defmodule M do
                 def f(x), do = x + 1
               end
               """)
    end

    test "in a for comprehension with block" do
      assert [%Issue{rule: :fix_do_equals_keyword_syntax}] =
               analyze("""
               defmodule FixDoEquals do
                 def build(list) do
                   for x <- list, do = x + 1 do
                     result
                   end
                 end
               end
               """)
    end
  end

  describe "leaves valid code alone" do
    test "do: keyword syntax" do
      assert analyze("""
             defmodule M do
               def f(x), do: x + 1
             end
             """) == []
    end

    test "do block syntax" do
      assert analyze("""
             defmodule M do
               def f(x) do
                 x + 1
               end
             end
             """) == []
    end

    test "comment lines with do =" do
      assert analyze("""
             defmodule M do
               # def f(x), do = x + 1
               def f(x), do: x + 1
             end
             """) == []
    end
  end
end
