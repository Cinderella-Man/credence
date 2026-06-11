defmodule Credence.Syntax.FixDoBlockFusionAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixDoBlockFusion

  defp analyze(code), do: FixDoBlockFusion.analyze(code)

  describe "flags do-block / one-liner fusions" do
    test "comma-do at end of line" do
      assert [%Issue{} | _] =
               analyze("""
               defmodule Solution do
                 def push(stack, value), do
                   [value | stack]
                 end
               end
               """)
    end

    test "doubled do opener" do
      assert [%Issue{} | _] =
               analyze("""
               defmodule Solution do
                 def double(n) do do
                   n * 2
                 end
               end
               """)
    end

    test "do: fused after the paren with a stray trailing end" do
      assert [%Issue{} | _] =
               analyze("""
               defmodule Solution do
                 def double(n) do: n * 2 end
               end
               """)
    end

    test "midline comma-do missing its colon" do
      assert [%Issue{} | _] =
               analyze("""
               defmodule Solution do
                 def inc(x), do x + 1
               end
               """)
    end
  end

  describe "leaves valid code alone" do
    test "well-formed block and one-liner forms are not flagged" do
      assert analyze("""
             defmodule Solution do
               def inc(x), do: x + 1

               def push(stack, value) do
                 [value | stack]
               end
             end
             """) == []
    end

    test "comment lines are ignored" do
      assert analyze("""
             defmodule Solution do
               # def f(x), do
               def f(x), do: x
             end
             """) == []
    end
  end
end
