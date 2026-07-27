defmodule Credence.Syntax.FixEtsOptionsBareKeyposAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixEtsOptionsBareKeypos

  defp analyze(code), do: FixEtsOptionsBareKeypos.analyze(code)

  describe "flags bare :keypos pattern" do
    test "bare :keypos with integer" do
      assert [%Issue{rule: :fix_ets_options_bare_keypos}] = analyze(":keypos, 1")
    end

    test "in ets.new call" do
      input = ":ets.new(:my_table, [:named_table, :set, :public, :keypos, 1])"
      assert [%Issue{rule: :fix_ets_options_bare_keypos}] = analyze(input)
    end

    test "in multiline ets.new call" do
      input = """
      :ets.new(:my_table, [
        :named_table,
        :set,
        :public,
        :keypos, 1
      ])
      """

      assert [%Issue{rule: :fix_ets_options_bare_keypos}] = analyze(input)
    end

    test "with different keypos value" do
      assert [%Issue{rule: :fix_ets_options_bare_keypos}] = analyze(":keypos, 3")
    end
  end

  describe "leaves good code alone" do
    test "correct tuple syntax" do
      assert analyze("{:keypos, 1}") == []
    end

    test "correct ets.new call" do
      input = ":ets.new(:my_table, [:named_table, :set, :public, {:keypos, 1}])"
      assert analyze(input) == []
    end

    test "other ets options without keypos" do
      assert analyze(":ets.new(:my_table, [:named_table, :set, :public])") == []
    end

    test "comment with pattern is ignored" do
      assert analyze("# :keypos, 1") == []
    end
  end
end
