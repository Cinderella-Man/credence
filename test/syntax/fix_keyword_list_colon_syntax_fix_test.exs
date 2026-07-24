defmodule Credence.Syntax.FixKeywordListColonSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixKeywordListColonSyntax

  defp analyze(code), do: FixKeywordListColonSyntax.analyze(code)
  defp fix(code), do: FixKeywordListColonSyntax.fix(code)

  describe "fixes the colon-on-wrong-side pattern" do
    test "single keyword" do
      input = ":read_concurrency: true"

      expected = "read_concurrency: true"

      confirm_fix(fix(input), expected)
    end

    test "in ETS options list" do
      input = """
      :ets.new(table_name, [
        :set,
        :named_table,
        :public,
        :read_concurrency: true
      ])
      """

      expected = """
      :ets.new(table_name, [
        :set,
        :named_table,
        :public,
        read_concurrency: true
      ])
      """

      confirm_fix(fix(input), expected)
    end

    test "multiple on different lines" do
      input = """
      [
        :key1: val1,
        :key2: val2
      ]
      """

      expected = """
      [
        key1: val1,
        key2: val2
      ]
      """

      confirm_fix(fix(input), expected)
    end

    test "with question mark suffix" do
      input = "[valid: 1, :ready?: true]"

      expected = "[valid: 1, ready?: true]"

      confirm_fix(fix(input), expected)
    end

    test "with exclamation mark suffix" do
      input = "[valid: 1, :danger!: false]"

      expected = "[valid: 1, danger!: false]"

      confirm_fix(fix(input), expected)
    end
  end

  describe "touches only the offending colon, never surrounding text" do
    # The real bug sits next to a string that also contains the `:ident:` shape.
    # Position-targeting fixes only the code and leaves the string byte-for-byte.
    test "preserves a string literal on another line" do
      input = """
      x = "keep :this: text"
      [a: 1, :foo: 2]
      """

      expected = """
      x = "keep :this: text"
      [a: 1, foo: 2]
      """

      confirm_fix(fix(input), expected)
    end
  end

  describe "leaves correct code unchanged" do
    test "correct keyword syntax" do
      code = "read_concurrency: true"
      confirm_fix(fix(code), code)
    end

    test "bare atoms" do
      code = ":set"
      confirm_fix(fix(code), code)
    end

    test "keyword list" do
      code = "[key: value, other: 42]"
      confirm_fix(fix(code), code)
    end
  end

  describe "does not corrupt the pattern inside text when the file is broken elsewhere" do
    test "string literal is left intact" do
      code = """
      x = "opt :read_concurrency: yes"
      def broken(
      """

      confirm_fix(fix(code), code)
    end

    test "inline comment is left intact" do
      code = "foo(1 # note :read_concurrency: here"

      confirm_fix(fix(code), code)
    end

    test "heredoc content is left intact" do
      code = """
      @moduledoc \"\"\"
      Example: :read_concurrency: true
      \"\"\"
      def broken(
      """

      confirm_fix(fix(code), code)
    end
  end

  describe "fixed output no longer flags" do
    test "single keyword" do
      assert analyze(fix(":read_concurrency: true")) == []
    end

    test "in ETS options list" do
      input = """
      :ets.new(table_name, [
        :set,
        :named_table,
        :public,
        :read_concurrency: true
      ])
      """

      assert analyze(fix(input)) == []
    end
  end

  describe "fixed output is well-formed (parses)" do
    test "in ETS options list" do
      input = """
      :ets.new(table_name, [
        :set,
        :named_table,
        :public,
        :read_concurrency: true
      ])
      """

      assert valid_syntax?(fix(input))
    end

    test "single keyword in list context" do
      assert valid_syntax?(fix("[key: :val, :read_concurrency: true]"))
    end
  end
end
