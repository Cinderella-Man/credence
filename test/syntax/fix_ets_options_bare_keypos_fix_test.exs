defmodule Credence.Syntax.FixEtsOptionsBareKeyposFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixEtsOptionsBareKeypos

  defp analyze(code), do: FixEtsOptionsBareKeypos.analyze(code)
  defp fix(code), do: FixEtsOptionsBareKeypos.fix(code)

  describe "fixes the bare keypos pattern" do
    test "simple bare keypos" do
      input = ":ets.new(:my_table, [:named_table, :set, :public, :keypos, 1])"
      expected = ":ets.new(:my_table, [:named_table, :set, :public, {:keypos, 1}])"
      confirm_fix(fix(input), expected)
    end

    test "bare keypos with different value" do
      input = ":ets.new(:my_table, [:set, :keypos, 3])"
      expected = ":ets.new(:my_table, [:set, {:keypos, 3}])"
      confirm_fix(fix(input), expected)
    end

    test "multiline ets.new call" do
      input = """
      :ets.new(:my_table, [
        :named_table,
        :set,
        :public,
        :keypos, 1
      ])
      """

      expected = """
      :ets.new(:my_table, [
        :named_table,
        :set,
        :public,
        {:keypos, 1}
      ])
      """

      confirm_fix(fix(input), expected)
    end

    test "in module" do
      input = ~S"""
      defmodule FixEtsOptionsBareKeypos do
        def create_table do
          :ets.new(:my_table, [:named_table, :set, :public, :keypos, 1])
        end
      end
      """

      expected = ~S"""
      defmodule FixEtsOptionsBareKeypos do
        def create_table do
          :ets.new(:my_table, [:named_table, :set, :public, {:keypos, 1}])
        end
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  describe "leaves correct code unchanged" do
    test "correct tuple syntax" do
      code = "{:keypos, 1}"
      confirm_fix(fix(code), code)
    end

    test "correct ets.new call" do
      code = ":ets.new(:my_table, [:named_table, :set, :public, {:keypos, 1}])"
      confirm_fix(fix(code), code)
    end

    test "other ets options without keypos" do
      code = ":ets.new(:my_table, [:named_table, :set, :public])"
      confirm_fix(fix(code), code)
    end
  end

  describe "fixed output no longer flags" do
    test "simple bare keypos" do
      assert analyze(fix(":keypos, 1")) == []
    end

    test "in ets.new call" do
      input = ":ets.new(:my_table, [:named_table, :set, :public, :keypos, 1])"
      assert analyze(fix(input)) == []
    end
  end

  describe "fixed output is well-formed (parses)" do
    test "simple bare keypos" do
      assert valid_syntax?(fix(":ets.new(:my_table, [:named_table, :set, :public, :keypos, 1])"))
    end

    test "multiline ets.new call" do
      input = """
      :ets.new(:my_table, [
        :named_table,
        :set,
        :public,
        :keypos, 1
      ])
      """

      assert valid_syntax?(fix(input))
    end
  end
end
