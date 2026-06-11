defmodule Credence.Syntax.FixTruncatedBinaryCloseAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixTruncatedBinaryClose

  defp analyze(code), do: FixTruncatedBinaryClose.analyze(code)

  describe "flags truncated binary close" do
    test "inside list constructor with nested call" do
      assert [%Issue{rule: :fix_truncated_binary_close}] =
               analyze("""
               [result | insert(char, <<first, rest::binary>)]\
               """)
    end

    test "in assignment with nested call" do
      assert [%Issue{rule: :fix_truncated_binary_close}] =
               analyze("""
               result = insert(char, <<first, rest::binary>)\
               """)
    end

    test "multiple occurrences" do
      assert [%Issue{}, %Issue{}] =
               analyze("""
               x = <<first, rest::binary>)
               y = <<second, tail::binary>)\
               """)
    end
  end

  describe "leaves good code alone" do
    test "correctly closed binary without truncation" do
      assert analyze("""
             result = <<first, char, rest::binary>>\
             """) == []
    end

    test "plain code without binary pattern" do
      assert analyze("""
             foo(bar)\
             """) == []
    end

    test "binary in function head is correct" do
      assert analyze("""
             def insert(char, <<first, rest::binary>>) do\
             """) == []
    end
  end
end
