defmodule Credence.Pattern.NoRedundantListTraversalFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantListTraversal

  # ═══════════════════════════════════════════════════════════════════
  # length + Enum.sum → not touched, and no longer reported either
  #
  # These used to be "reported as a hint, declined by the fix" — the
  # report-without-repair shape CONTEXT.md forbids. `length/1`,
  # `Enum.count/1` and `Enum.sum/1` are no longer tracked at all, so
  # these are now byte-identical for the plainer reason that the rule
  # sees nothing in them. Kept as scope documentation; the check-side
  # counterparts in the check test are the ones that pin it.
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves length + Enum.sum untouched" do
    test "basic case — count then sum" do
      input = """
      def run(numbers) do
        count = length(numbers)
        sum = Enum.sum(numbers)
        {count, sum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "Enum.count + Enum.sum" do
      input = """
      def run(numbers) do
        count = Enum.count(numbers)
        sum = Enum.sum(numbers)
        sum / count
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "preserves intervening code" do
      input = """
      def run(numbers) do
        count = length(numbers)
        expected = div(count * (count + 1), 2)
        actual = Enum.sum(numbers)
        expected - actual
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "flipped order — sum first, then length" do
      input = """
      def run(numbers) do
        sum = Enum.sum(numbers)
        count = length(numbers)
        sum / count
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "inside a full module" do
      input = """
      defmodule Stats do
        def average(numbers) do
          count = length(numbers)
          sum = Enum.sum(numbers)
          sum / count
        end
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Enum.min + Enum.max → Enum.min_max
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes Enum.min + Enum.max into Enum.min_max" do
    test "basic case" do
      input = """
      def run(numbers) do
        minimum = Enum.min(numbers)
        maximum = Enum.max(numbers)
        {minimum, maximum}
      end
      """

      expected = """
      def run(numbers) do
        {minimum, maximum} = Enum.min_max(numbers)
        {minimum, maximum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), expected)
    end

    test "flipped order — max first" do
      input = """
      def run(numbers) do
        maximum = Enum.max(numbers)
        minimum = Enum.min(numbers)
        maximum - minimum
      end
      """

      expected = """
      def run(numbers) do
        {minimum, maximum} = Enum.min_max(numbers)
        maximum - minimum
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), expected)
    end

    test "with intervening code" do
      input = """
      def run(numbers) do
        minimum = Enum.min(numbers)
        IO.puts("got min")
        maximum = Enum.max(numbers)
        maximum - minimum
      end
      """

      expected = """
      def run(numbers) do
        {minimum, maximum} = Enum.min_max(numbers)
        IO.puts("got min")
        maximum - minimum
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify inline calls in the same expression" do
    test "min and max in one expression" do
      input = """
      def run(numbers) do
        spread = Enum.max(numbers) - Enum.min(numbers)
        Enum.filter(numbers, &(&1 >= average))
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "min and max in one division" do
      input = """
      def run(numbers) do
        ratio = Enum.max(numbers) / Enum.min(numbers)
        average
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "Enum.min + Enum.max in same expression" do
      input = """
      def run(numbers) do
        diff = Enum.max(numbers) - Enum.min(numbers)
        diff
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "min and max added together" do
      input = """
      def run(numbers) do
        result = Enum.min(numbers) + Enum.max(numbers)
        result
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end

  describe "does not modify when variables differ" do
    test "length on a, sum on b" do
      input = """
      def run(a, b) do
        count = length(a)
        sum = Enum.sum(b)
        {count, sum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end

  describe "does not modify when variable is rebound" do
    test "list reassigned between calls" do
      input = """
      def run(numbers) do
        count = length(numbers)
        numbers = Enum.filter(numbers, &(&1 > 0))
        sum = Enum.sum(numbers)
        {count, sum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end

  describe "does not modify calls in different blocks" do
    test "one in body, one inside if" do
      input = """
      def run(numbers) do
        count = length(numbers)
        if count > 0 do
          sum = Enum.sum(numbers)
          sum / count
        end
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # One bare + one inline → merged with generated variable
  # ═══════════════════════════════════════════════════════════════════

  describe "does not auto-fix bare assignment + inline count/sum call" do
    test "bare length + inline Enum.sum — exact idx=33 pattern" do
      input = """
      def run(numbers) do
        n = length(numbers)
        div(n * (n + 1), 2) - Enum.sum(numbers)
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "bare length + inline Enum.sum in assignment RHS" do
      input = """
      def run(numbers) do
        count = length(numbers)
        doubled_sum = Enum.sum(numbers) * 2
        {count, doubled_sum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "bare Enum.sum + inline length in assignment RHS" do
      input = """
      def run(numbers) do
        half_count = div(length(numbers), 2)
        sum = Enum.sum(numbers)
        {half_count, sum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "bare Enum.min + inline Enum.max" do
      input = """
      def run(numbers) do
        minimum = Enum.min(numbers)
        minimum + Enum.max(numbers)
      end
      """

      expected = """
      def run(numbers) do
        {minimum, maximum} = Enum.min_max(numbers)
        minimum + maximum
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), expected)
    end

    test "bare Enum.max + inline Enum.min in assignment" do
      input = """
      def run(numbers) do
        maximum = Enum.max(numbers)
        offset_min = Enum.min(numbers) + 10
        maximum - offset_min
      end
      """

      expected = """
      def run(numbers) do
        {minimum, maximum} = Enum.min_max(numbers)
        offset_min = minimum + 10
        maximum - offset_min
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), expected)
    end
  end

  describe "does not modify single traversals" do
    test "only length, no sum" do
      input = """
      def run(numbers) do
        count = length(numbers)
        count * 2
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end

  describe "does not modify when argument is not a variable" do
    test "function call as argument" do
      input = """
      def run do
        count = length(get_list())
        sum = Enum.sum(get_list())
        {count, sum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "field access as argument" do
      input = """
      def run(state) do
        count = length(state.numbers)
        sum = Enum.sum(state.numbers)
        {count, sum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end

  describe "does not modify arity-2 variants" do
    test "Enum.count with filter" do
      input = """
      def run(numbers) do
        positives = Enum.count(numbers, &(&1 > 0))
        sum = Enum.sum(numbers)
        {positives, sum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end

  describe "does not modify discarded assignments" do
    test "underscore on one side" do
      input = """
      def run(numbers) do
        _ = length(numbers)
        sum = Enum.sum(numbers)
        sum
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end

  describe "does not modify already-optimal code" do
    test "no traversal functions at all" do
      input = """
      defmodule Example do
        def run(n), do: n * 2
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end

    test "already uses Enum.min_max" do
      input = """
      def run(numbers) do
        {minimum, maximum} = Enum.min_max(numbers)
        {minimum, maximum}
      end
      """

      confirm_fix(fix(NoRedundantListTraversal, input), input)
    end
  end
end
