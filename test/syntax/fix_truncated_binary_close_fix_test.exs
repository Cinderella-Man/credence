defmodule Credence.Syntax.FixTruncatedBinaryCloseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixTruncatedBinaryClose

  defp analyze(code), do: FixTruncatedBinaryClose.analyze(code)
  defp fix(code), do: FixTruncatedBinaryClose.fix(code)

  describe "fixes truncated binary close" do
    test "inside list constructor with nested call" do
      input = "[result | insert(char, <<first, rest::binary>)]"

      expected = "[result | insert(char, <<first, rest::binary>>)]"

      confirm_fix(fix(input), expected)
    end

    test "in assignment with nested call" do
      input = "result = insert(char, <<first, rest::binary>)"

      expected = "result = insert(char, <<first, rest::binary>>)"

      confirm_fix(fix(input), expected)
    end

    test "multiple occurrences on different lines" do
      input = """
      x = <<first, rest::binary>)
      y = <<second, tail::binary>)
      """

      expected = """
      x = <<first, rest::binary>>)
      y = <<second, tail::binary>>)
      """

      confirm_fix(fix(input), expected)
    end
  end

  describe "leaves correct code unchanged" do
    test "properly closed binary without truncation" do
      code = "result = <<first, char, rest::binary>>"

      confirm_fix(fix(code), code)
    end

    test "plain code without binary pattern" do
      code = "foo(bar)"

      confirm_fix(fix(code), code)
    end

    test "binary in function head is correct" do
      code = "def insert(char, <<first, rest::binary>>) do"

      confirm_fix(fix(code), code)
    end
  end

  describe "fixed output no longer flags" do
    test "inside list constructor" do
      assert analyze(fix("[result | insert(char, <<first, rest::binary>)]")) == []
    end

    test "in assignment" do
      assert analyze(fix("result = insert(char, <<first, rest::binary>)")) == []
    end
  end

  describe "fixed output is well-formed (parses)" do
    test "inside list constructor" do
      assert valid_syntax?(fix("[result | insert(char, <<first, rest::binary>)]"))
    end

    test "in assignment" do
      assert valid_syntax?(fix("result = insert(char, <<first, rest::binary>)"))
    end
  end
end
