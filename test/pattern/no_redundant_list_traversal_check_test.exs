defmodule Credence.Pattern.NoRedundantListTraversalCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoRedundantListTraversal.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — length + Enum.sum
  # ═══════════════════════════════════════════════════════════════════

  describe "flags length + Enum.sum on same variable" do
    test "basic case" do
      assert flagged?("""
             def run(numbers) do
               count = length(numbers)
               sum = Enum.sum(numbers)
               {count, sum}
             end
             """)
    end

    test "Enum.count variant" do
      assert flagged?("""
             def run(numbers) do
               count = Enum.count(numbers)
               sum = Enum.sum(numbers)
               {count, sum}
             end
             """)
    end

    test "with intervening code between calls" do
      assert flagged?("""
             def run(numbers) do
               count = length(numbers)
               expected = div(count * (count + 1), 2)
               actual = Enum.sum(numbers)
               expected - actual
             end
             """)
    end

    test "flipped order — sum before length" do
      assert flagged?("""
             def run(numbers) do
               sum = Enum.sum(numbers)
               count = length(numbers)
               sum / count
             end
             """)
    end

    test "inside a module" do
      assert flagged?("""
             defmodule Stats do
               def average(numbers) do
                 count = length(numbers)
                 sum = Enum.sum(numbers)
                 sum / count
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — Enum.min + Enum.max
  # ═══════════════════════════════════════════════════════════════════

  describe "flags Enum.min + Enum.max on same variable" do
    test "basic case" do
      assert flagged?("""
             def run(numbers) do
               minimum = Enum.min(numbers)
               maximum = Enum.max(numbers)
               {minimum, maximum}
             end
             """)
    end

    test "flipped order" do
      assert flagged?("""
             def run(numbers) do
               maximum = Enum.max(numbers)
               minimum = Enum.min(numbers)
               maximum - minimum
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — cross-category pairs
  # ═══════════════════════════════════════════════════════════════════

  describe "flags other pairs" do
    test "length + Enum.max" do
      assert flagged?("""
             def run(numbers) do
               count = length(numbers)
               maximum = Enum.max(numbers)
               {count, maximum}
             end
             """)
    end

    test "Enum.sum + Enum.min" do
      assert flagged?("""
             def run(numbers) do
               sum = Enum.sum(numbers)
               minimum = Enum.min(numbers)
               {sum, minimum}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — triple traversal
  # ═══════════════════════════════════════════════════════════════════

  describe "flags three or more traversals" do
    test "length + sum + max" do
      assert flagged?("""
             def run(numbers) do
               count = length(numbers)
               sum = Enum.sum(numbers)
               maximum = Enum.max(numbers)
               {count, sum, maximum}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — nested blocks
  # ═══════════════════════════════════════════════════════════════════

  describe "flags pairs in nested blocks" do
    test "both inside an if body" do
      assert flagged?("""
             def run(numbers) do
               if numbers != [] do
                 count = length(numbers)
                 sum = Enum.sum(numbers)
                 sum / count
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — different variables
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag different variables" do
    test "length on one var, sum on another" do
      assert clean?("""
             def run(a, b) do
               count = length(a)
               sum = Enum.sum(b)
               {count, sum}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — variable rebound between calls
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when variable is rebound" do
    test "list reassigned between length and sum" do
      assert clean?("""
             def run(numbers) do
               count = length(numbers)
               numbers = Enum.filter(numbers, &(&1 > 0))
               sum = Enum.sum(numbers)
               {count, sum}
             end
             """)
    end

    test "list reassigned via pattern match" do
      assert clean?("""
             def run(numbers) do
               count = length(numbers)
               [_ | numbers] = numbers
               sum = Enum.sum(numbers)
               {count, sum}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — different blocks / scopes
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag calls in different blocks" do
    test "one in function body, one inside if" do
      assert clean?("""
             def run(numbers) do
               count = length(numbers)
               if count > 0 do
                 sum = Enum.sum(numbers)
                 sum / count
               end
             end
             """)
    end

    test "one in if-true branch, one in if-false branch" do
      assert clean?("""
             def run(numbers, mode) do
               if mode == :count do
                 count = length(numbers)
                 count
               else
                 sum = Enum.sum(numbers)
                 sum
               end
             end
             """)
    end

    test "separate functions in the same module" do
      assert clean?("""
             defmodule Stats do
               def count(numbers), do: length(numbers)
               def total(numbers), do: Enum.sum(numbers)
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — non-bare assignments
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when call is nested in a larger expression" do
    test "length inside arithmetic" do
      assert clean?("""
             def run(numbers) do
               half_count = div(length(numbers), 2)
               sum = Enum.sum(numbers)
               {half_count, sum}
             end
             """)
    end

    test "Enum.sum inside arithmetic" do
      assert clean?("""
             def run(numbers) do
               count = length(numbers)
               doubled_sum = Enum.sum(numbers) * 2
               {count, doubled_sum}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — argument is not a plain variable
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when argument is not a variable" do
    test "function call as argument" do
      assert clean?("""
             def run do
               count = length(get_list())
               sum = Enum.sum(get_list())
               {count, sum}
             end
             """)
    end

    test "field access as argument" do
      assert clean?("""
             def run(state) do
               count = length(state.numbers)
               sum = Enum.sum(state.numbers)
               {count, sum}
             end
             """)
    end

    test "map access as argument" do
      assert clean?("""
             def run(data) do
               count = length(data[:numbers])
               sum = Enum.sum(data[:numbers])
               {count, sum}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — arity-2 variants (filtered counts, custom comparators)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag arity-2 variants" do
    test "Enum.count with filter function" do
      assert clean?("""
             def run(numbers) do
               positives = Enum.count(numbers, &(&1 > 0))
               sum = Enum.sum(numbers)
               {positives, sum}
             end
             """)
    end

    test "Enum.min with sorter" do
      assert clean?("""
             def run(items) do
               smallest = Enum.min(items, &compare/2)
               largest = Enum.max(items, &compare/2)
               {smallest, largest}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — single traversal, same function twice, discarded
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag single traversal" do
    test "only length" do
      assert clean?("""
             def run(numbers) do
               count = length(numbers)
               count * 2
             end
             """)
    end

    test "only Enum.sum" do
      assert clean?("""
             def run(numbers) do
               sum = Enum.sum(numbers)
               sum * 2
             end
             """)
    end
  end

  describe "does not flag same function called twice" do
    test "length called twice" do
      assert clean?("""
             def run(numbers) do
               a = length(numbers)
               b = length(numbers)
               a + b
             end
             """)
    end
  end

  describe "does not flag discarded assignments" do
    test "underscore binding for one call" do
      assert clean?("""
             def run(numbers) do
               _ = length(numbers)
               sum = Enum.sum(numbers)
               sum
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — already optimal
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag already-optimal code" do
    test "Enum.min_max already used" do
      assert clean?("""
             def run(numbers) do
               {minimum, maximum} = Enum.min_max(numbers)
               {minimum, maximum}
             end
             """)
    end

    test "Enum.reduce already used" do
      assert clean?("""
             def run(numbers) do
               {count, sum} = Enum.reduce(numbers, {0, 0}, fn x, {c, s} -> {c + 1, s + x} end)
               {count, sum}
             end
             """)
    end
  end
end
