defmodule Credence.Pattern.NoDoubleFilterTest do
  use ExUnit.Case

  alias Credence.Pattern.NoDoubleFilter

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoDoubleFilter.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags two Enum.filter on same enumerable" do
    test "basic complementary predicates" do
      assert flagged?("""
             def split(numbers) do
               non_neg = Enum.filter(numbers, &(&1 >= 0))
               neg = Enum.filter(numbers, &(&1 < 0))
               {non_neg, neg}
             end
             """)
    end

    test "with different predicates" do
      assert flagged?("""
             def categorize(items) do
               evens = Enum.filter(items, &(rem(&1, 2) == 0))
               odds = Enum.filter(items, &(rem(&1, 2) != 0))
               {evens, odds}
             end
             """)
    end

    test "three filters on same enumerable" do
      assert flagged?("""
             def tri_split(list) do
               a = Enum.filter(list, &(&1 > 0))
               b = Enum.filter(list, &(&1 < 0))
               c = Enum.filter(list, &(&1 == 0))
               {a, b, c}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag single Enum.filter" do
    test "one filter call" do
      assert clean?("""
             def positives(numbers) do
               Enum.filter(numbers, &(&1 >= 0))
             end
             """)
    end

    test "one filter assigned" do
      assert clean?("""
             def positives(numbers) do
               result = Enum.filter(numbers, &(&1 >= 0))
               result
             end
             """)
    end
  end

  describe "does not flag filters on different enumerables" do
    test "two different variables" do
      assert clean?("""
             def process(a, b) do
               x = Enum.filter(a, &(&1 >= 0))
               y = Enum.filter(b, &(&1 < 0))
               {x, y}
             end
             """)
    end
  end

  describe "does not flag Enum.filter with other Enum functions" do
    test "filter then map on same enumerable" do
      assert clean?("""
             def process(list) do
               filtered = Enum.filter(list, &(&1 >= 0))
               mapped = Enum.map(list, &(&1 * 2))
               {filtered, mapped}
             end
             """)
    end
  end

  describe "does not flag Enum.split_with usage" do
    test "already using split_with" do
      assert clean?("""
             def split(numbers) do
               Enum.split_with(numbers, &(&1 >= 0))
             end
             """)
    end
  end
end
