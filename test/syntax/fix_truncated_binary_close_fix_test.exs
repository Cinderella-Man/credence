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

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — the truncated delimiter named in prose is not a delimiter
  #
  # The pattern is a bare literal with no guard of any kind, so every
  # mention was rewritten. Found by running the rule over its own source
  # file, four lines of which it edited.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — string literals are not code" do
    test "leaves the delimiter named inside a string alone" do
      code = ~S'IO.puts("the bug truncates <<x::binary>) here")'

      confirm_fix(fix(code), code)
    end

    test "leaves the string alone while still fixing real code on the same line" do
      confirm_fix(
        fix(~S'IO.puts("bug: <<x::binary>)"); y = f(<<a, r::binary>)'),
        ~S'IO.puts("bug: <<x::binary>)"); y = f(<<a, r::binary>>)'
      )
    end

    test "leaves a trailing comment alone while fixing the code before it" do
      confirm_fix(
        fix("y = f(<<a, r::binary>)  # was <<a, r::binary>)"),
        "y = f(<<a, r::binary>>)  # was <<a, r::binary>)"
      )
    end

    test "leaves a heredoc body alone" do
      code = ~S'''
      @moduledoc """
      LLMs truncate this to <<x::binary>) in nested calls.
      """
      '''

      confirm_fix(fix(code), code)
    end

    test "leaves an uppercase sigil alone" do
      code = ~S'IO.puts(~S(raw <<x::binary>)))'

      confirm_fix(fix(code), code)
    end

    test "does not report a string-only mention" do
      assert analyze(~S'IO.puts("the bug truncates <<x::binary>) here")') == []
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/fix_truncated_binary_close.ex")

      confirm_fix(fix(source), source)
    end
  end
end
