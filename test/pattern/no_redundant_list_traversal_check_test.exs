defmodule Credence.Pattern.NoRedundantListTraversalCheckTest do
  @moduledoc """
  Every negative here uses `Enum.min`/`Enum.max`, and that is deliberate.

  This rule used to track `length/1`, `Enum.count/1` and `Enum.sum/1` as well,
  and most of these negatives were written with a `length` + `Enum.sum` pair. On
  2026-08-17 those stopped being tracked at all — they had no repairable pair and
  they were suppressing a repairable one. The moment that landed, 28 of the 45
  fixtures in this file contained no tracked call whatsoever, so every negative
  passed by having nothing to look at: the rebinding check, the scope check, the
  arity-2 check and the not-a-plain-variable check would all have stayed green
  with their logic deleted.

  A negative fixture has to be one the rule would flag if the mechanism under
  test were broken. Rewritten accordingly.
  """
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantListTraversal

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — the one repairable pair
  # ═══════════════════════════════════════════════════════════════════

  describe "flags Enum.min + Enum.max on same variable" do
    test "basic case" do
      assert flagged?(NoRedundantListTraversal, """
             def run(numbers) do
               minimum = Enum.min(numbers)
               maximum = Enum.max(numbers)
               {minimum, maximum}
             end
             """)
    end

    test "flipped order" do
      assert flagged?(NoRedundantListTraversal, """
             def run(numbers) do
               maximum = Enum.max(numbers)
               minimum = Enum.min(numbers)
               maximum - minimum
             end
             """)
    end

    test "inside a module" do
      assert flagged?(NoRedundantListTraversal, """
             defmodule SpreadStats do
               def spread(numbers) do
                 minimum = Enum.min(numbers)
                 maximum = Enum.max(numbers)
                 maximum - minimum
               end
             end
             """)
    end

    test "with intervening code between the two calls" do
      assert flagged?(NoRedundantListTraversal, """
             def run(numbers) do
               minimum = Enum.min(numbers)
               label = "spread"
               maximum = Enum.max(numbers)
               {label, maximum - minimum}
             end
             """)
    end

    test "both inside an if body" do
      assert flagged?(NoRedundantListTraversal, """
             def run(numbers) do
               if numbers != [] do
                 minimum = Enum.min(numbers)
                 maximum = Enum.max(numbers)
                 maximum - minimum
               end
             end
             """)
    end
  end

  describe "flags when one call is bare and the other is inline" do
    test "bare Enum.min + inline Enum.max" do
      assert flagged?(NoRedundantListTraversal, """
             def run(numbers) do
               minimum = Enum.min(numbers)
               minimum + Enum.max(numbers)
             end
             """)
    end

    test "bare Enum.max + inline Enum.min in assignment" do
      assert flagged?(NoRedundantListTraversal, """
             def run(numbers) do
               maximum = Enum.max(numbers)
               offset_min = Enum.min(numbers) + 10
               maximum - offset_min
             end
             """)
    end
  end

  # A `length/1` sharing the block must not suppress the pair. Getting this
  # wrong is exactly what the first pass at the scope change did: `length/1` was
  # still tracked, so it joined the group, the group had three members, and
  # `find_fixable_groups/1` — which requires exactly the two members of a
  # fixable pair — threw the whole thing away.
  describe "flags min + max even when an untracked traversal shares the block" do
    test "a length/1 on the same list" do
      assert flagged?(NoRedundantListTraversal, """
             def run(numbers) do
               minimum = Enum.min(numbers)
               maximum = Enum.max(numbers)
               count = length(numbers)
               {minimum, maximum, count}
             end
             """)
    end

    test "an Enum.sum/1 on the same list" do
      assert flagged?(NoRedundantListTraversal, """
             def run(numbers) do
               total = Enum.sum(numbers)
               minimum = Enum.min(numbers)
               maximum = Enum.max(numbers)
               {total, minimum, maximum}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — the pairs with no single-pass form
  #
  # These document the SCOPE decision rather than a mechanism. `Enum.min_max/1`
  # exists; there is no stdlib `count_and_sum`, and `length/1` + `Enum.sum/1` is
  # the idiomatic mean, so hand-building a reduce would be a readability
  # downgrade. The rule reported these as a "consider merging" hint and never
  # repaired one — a finding a user sees and nothing fixes, which is what
  # CONTEXT.md's "fix or drop it" forbids and what
  # test/fix_or_drop_test.exs now gates for every rule.
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag pairs it has nothing to rewrite into" do
    test "length + Enum.sum" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               count = length(numbers)
               sum = Enum.sum(numbers)
               {count, sum}
             end
             """)
    end

    test "Enum.count + Enum.sum" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               count = Enum.count(numbers)
               sum = Enum.sum(numbers)
               {count, sum}
             end
             """)
    end

    test "length + Enum.max" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               count = length(numbers)
               maximum = Enum.max(numbers)
               {count, maximum}
             end
             """)
    end

    test "Enum.sum + Enum.min" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               sum = Enum.sum(numbers)
               minimum = Enum.min(numbers)
               {sum, minimum}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — mechanisms. Each fixture below WOULD be flagged if the
  # single mechanism it names stopped working.
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag different variables" do
    test "min on one var, max on another" do
      assert clean?(NoRedundantListTraversal, """
             def run(a, b) do
               minimum = Enum.min(a)
               maximum = Enum.max(b)
               {minimum, maximum}
             end
             """)
    end
  end

  describe "does not flag when the list is rebound between the calls" do
    test "reassigned by a plain match" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               minimum = Enum.min(numbers)
               numbers = Enum.filter(numbers, &(&1 > 0))
               maximum = Enum.max(numbers)
               {minimum, maximum}
             end
             """)
    end

    test "reassigned via a pattern match" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               minimum = Enum.min(numbers)
               [_ | numbers] = numbers
               maximum = Enum.max(numbers)
               {minimum, maximum}
             end
             """)
    end
  end

  describe "does not flag calls in different blocks" do
    test "one in the function body, one inside an if" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               minimum = Enum.min(numbers)
               if minimum > 0 do
                 maximum = Enum.max(numbers)
                 maximum - minimum
               end
             end
             """)
    end

    test "one in each branch of an if" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers, mode) do
               if mode == :low do
                 minimum = Enum.min(numbers)
                 minimum
               else
                 maximum = Enum.max(numbers)
                 maximum
               end
             end
             """)
    end

    test "separate functions in the same module" do
      assert clean?(NoRedundantListTraversal, """
             defmodule SpreadParts do
               def low(numbers), do: Enum.min(numbers)
               def high(numbers), do: Enum.max(numbers)
             end
             """)
    end
  end

  describe "does not flag when the argument is not a plain variable" do
    test "function call as argument" do
      assert clean?(NoRedundantListTraversal, """
             def run do
               minimum = Enum.min(get_list())
               maximum = Enum.max(get_list())
               {minimum, maximum}
             end
             """)
    end

    test "field access as argument" do
      assert clean?(NoRedundantListTraversal, """
             def run(state) do
               minimum = Enum.min(state.numbers)
               maximum = Enum.max(state.numbers)
               {minimum, maximum}
             end
             """)
    end

    test "map access as argument" do
      assert clean?(NoRedundantListTraversal, """
             def run(data) do
               minimum = Enum.min(data[:numbers])
               maximum = Enum.max(data[:numbers])
               {minimum, maximum}
             end
             """)
    end
  end

  describe "does not flag arity-2 variants" do
    test "both with a custom sorter" do
      assert clean?(NoRedundantListTraversal, """
             def run(items) do
               smallest = Enum.min(items, &compare/2)
               largest = Enum.max(items, &compare/2)
               {smallest, largest}
             end
             """)
    end

    # Mixed arities: `Enum.min_max/1` cannot express a custom comparator on one
    # side only, so one arity-2 member is enough to disqualify the pair.
    test "one arity-2, one arity-1" do
      assert clean?(NoRedundantListTraversal, """
             def run(items) do
               smallest = Enum.min(items, &compare/2)
               largest = Enum.max(items)
               {smallest, largest}
             end
             """)
    end
  end

  describe "does not flag a single traversal" do
    test "only Enum.min" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               minimum = Enum.min(numbers)
               minimum * 2
             end
             """)
    end

    test "only Enum.max" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               maximum = Enum.max(numbers)
               maximum * 2
             end
             """)
    end
  end

  describe "does not flag the same function called twice" do
    test "Enum.min called twice" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               a = Enum.min(numbers)
               b = Enum.min(numbers)
               a + b
             end
             """)
    end
  end

  describe "does not flag discarded assignments" do
    test "underscore binding for one call" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               _ = Enum.min(numbers)
               maximum = Enum.max(numbers)
               maximum
             end
             """)
    end
  end

  # Both calls inside one expression is a natural compound, not a redundancy
  # worth hoisting into a preceding binding — `all_inline_same_statement?/1`.
  describe "does not flag inline calls in the same expression" do
    test "max - min in one expression" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               diff = Enum.max(numbers) - Enum.min(numbers)
               diff
             end
             """)
    end

    test "min and max added together" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               result = Enum.min(numbers) + Enum.max(numbers)
               result
             end
             """)
    end
  end

  describe "does not flag already-optimal code" do
    test "Enum.min_max already used" do
      assert clean?(NoRedundantListTraversal, """
             def run(numbers) do
               {minimum, maximum} = Enum.min_max(numbers)
               {minimum, maximum}
             end
             """)
    end
  end
end
