defmodule Credence.Pattern.NoDoubleFilterCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoDoubleFilter

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoDoubleFilter.check(ast, source: code)
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — adjacent, complementary filters on the same variable
  # ═══════════════════════════════════════════════════════════════════

  describe "flags adjacent complementary filters" do
    test "ge / lt" do
      assert flagged?("""
             def split(numbers) do
               non_neg = Enum.filter(numbers, &(&1 >= 0))
               neg = Enum.filter(numbers, &(&1 < 0))
               {non_neg, neg}
             end
             """)
    end

    test "gt / le" do
      assert flagged?("""
             def split(items) do
               big = Enum.filter(items, &(&1 > 10))
               small = Enum.filter(items, &(&1 <= 10))
               {big, small}
             end
             """)
    end

    test "eq / neq" do
      assert flagged?("""
             def split(items) do
               zeros = Enum.filter(items, &(&1 == 0))
               nonzeros = Enum.filter(items, &(&1 != 0))
               {zeros, nonzeros}
             end
             """)
    end

    test "operand is a bound variable" do
      assert flagged?("""
             def split(items, threshold) do
               keep = Enum.filter(items, &(&1 >= threshold))
               drop = Enum.filter(items, &(&1 < threshold))
               {keep, drop}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — deliberately dropped unsafe / out-of-core shapes
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag non-complementary predicates" do
    test "gt / lt leaves out the equal element — not a partition" do
      assert clean?("""
             def split(list) do
               pos = Enum.filter(list, &(&1 > 0))
               neg = Enum.filter(list, &(&1 < 0))
               {pos, neg}
             end
             """)
    end

    test "different operands" do
      assert clean?("""
             def split(list) do
               a = Enum.filter(list, &(&1 >= 0))
               b = Enum.filter(list, &(&1 < 5))
               {a, b}
             end
             """)
    end

    test "unrelated predicates" do
      assert clean?("""
             def categorize(items) do
               evens = Enum.filter(items, &(rem(&1, 2) == 0))
               odds = Enum.filter(items, &(rem(&1, 2) != 0))
               {evens, odds}
             end
             """)
    end
  end

  describe "does not flag operands with side effects" do
    test "operand is a call" do
      assert clean?("""
             def split(list) do
               a = Enum.filter(list, &(&1 >= limit()))
               b = Enum.filter(list, &(&1 < limit()))
               {a, b}
             end
             """)
    end
  end

  describe "does not flag non-adjacent filters" do
    test "statement between the two filters" do
      assert clean?("""
             def split(numbers) do
               non_neg = Enum.filter(numbers, &(&1 >= 0))
               log(non_neg)
               neg = Enum.filter(numbers, &(&1 < 0))
               {non_neg, neg}
             end
             """)
    end
  end

  describe "does not flag filters on different variables" do
    test "two different sources" do
      assert clean?("""
             def process(a, b) do
               x = Enum.filter(a, &(&1 >= 0))
               y = Enum.filter(b, &(&1 < 0))
               {x, y}
             end
             """)
    end
  end

  describe "does not flag a single filter" do
    test "one filter assigned" do
      assert clean?("""
             def positives(numbers) do
               result = Enum.filter(numbers, &(&1 >= 0))
               result
             end
             """)
    end
  end

  describe "does not flag the same bound variable twice" do
    test "v1 == v2 would produce {x, x} = ..." do
      assert clean?("""
             def split(numbers) do
               x = Enum.filter(numbers, &(&1 >= 0))
               x = Enum.filter(numbers, &(&1 < 0))
               {x}
             end
             """)
    end
  end

  describe "does not flag reversed-operand predicates" do
    test "operand on the left of the comparison" do
      assert clean?("""
             def split(numbers) do
               a = Enum.filter(numbers, &(0 <= &1))
               b = Enum.filter(numbers, &(0 > &1))
               {a, b}
             end
             """)
    end
  end
end
