defmodule Credence.Syntax.FixKeywordListColonSyntaxAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixKeywordListColonSyntax

  defp analyze(code), do: FixKeywordListColonSyntax.analyze(code)

  describe "flags the colon-on-wrong-side pattern" do
    test "single keyword" do
      assert [%Issue{rule: :fix_keyword_list_colon_syntax}] =
               analyze(":read_concurrency: true")
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

      assert [%Issue{rule: :fix_keyword_list_colon_syntax}] = analyze(input)
    end

    test "multiple on different lines" do
      input = """
      :key1: val1
      :key2: val2
      """

      assert [%Issue{}, %Issue{}] = analyze(input)
    end

    test "with question mark suffix" do
      assert [%Issue{rule: :fix_keyword_list_colon_syntax}] =
               analyze(":valid?: true")
    end

    test "with exclamation mark suffix" do
      assert [%Issue{rule: :fix_keyword_list_colon_syntax}] =
               analyze(":danger!: false")
    end
  end

  describe "leaves good code alone" do
    test "correct keyword syntax" do
      assert analyze("read_concurrency: true") == []
    end

    test "bare atoms" do
      assert analyze(":set") == []
      assert analyze(":named_table") == []
    end

    test "atom in map update" do
      assert analyze("%{var | key: value}") == []
    end

    test "normal function call" do
      assert analyze(~S'IO.puts("hello")') == []
    end

    test "keyword list with correct syntax" do
      assert analyze("[key: value, other: 42]") == []
    end

    test "comment with pattern is ignored" do
      assert analyze("# :foo: bar") == []
    end
  end
end
