defmodule Credence.Pattern.NoRedundantListTraversalFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRedundantListTraversal

  defp fix(code) do
    result =
      Credence.RuleHelpers.apply_rule_fix(NoRedundantListTraversal, code, [])

    # Sourceror.to_string/1 omits trailing newline; heredocs always include one.
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # length + Enum.sum → Enum.reduce
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes length + Enum.sum into Enum.reduce" do
    test "basic case" do
      input = """
      def run(numbers) do
        count = length(numbers)
        sum = Enum.sum(numbers)
        {count, sum}
      end
      """

      expected = """
      def run(numbers) do
        {count, sum} = Enum.reduce(numbers, {0, 0}, fn x, {c, s} -> {c + 1, s + x} end)
        {count, sum}
      end
      """

      assert fix(input) == expected
    end

    test "Enum.count + Enum.sum" do
      input = """
      def run(numbers) do
        count = Enum.count(numbers)
        sum = Enum.sum(numbers)
        sum / count
      end
      """

      expected = """
      def run(numbers) do
        {count, sum} = Enum.reduce(numbers, {0, 0}, fn x, {c, s} -> {c + 1, s + x} end)
        sum / count
      end
      """

      assert fix(input) == expected
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

      expected = """
      def run(numbers) do
        {count, actual} = Enum.reduce(numbers, {0, 0}, fn x, {c, s} -> {c + 1, s + x} end)
        expected = div(count * (count + 1), 2)
        expected - actual
      end
      """

      assert fix(input) == expected
    end

    test "flipped order — sum first, then length" do
      input = """
      def run(numbers) do
        sum = Enum.sum(numbers)
        count = length(numbers)
        sum / count
      end
      """

      expected = """
      def run(numbers) do
        {sum, count} = Enum.reduce(numbers, {0, 0}, fn x, {s, c} -> {s + x, c + 1} end)
        sum / count
      end
      """

      assert fix(input) == expected
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

      expected = """
      defmodule Stats do
        def average(numbers) do
          {count, sum} = Enum.reduce(numbers, {0, 0}, fn x, {c, s} -> {c + 1, s + x} end)
          sum / count
        end
      end
      """

      assert fix(input) == expected
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

      assert fix(input) == expected
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

      assert fix(input) == expected
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

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify inline calls in the same expression" do
    test "Enum.sum + length for average" do
      input = """
      def run(numbers) do
        average = Enum.sum(numbers) / length(numbers)
        Enum.filter(numbers, &(&1 >= average))
      end
      """

      assert fix(input) == input
    end

    test "Enum.sum + Enum.count for average" do
      input = """
      def run(numbers) do
        average = Enum.sum(numbers) / Enum.count(numbers)
        average
      end
      """

      assert fix(input) == input
    end

    test "Enum.min + Enum.max in same expression" do
      input = """
      def run(numbers) do
        diff = Enum.max(numbers) - Enum.min(numbers)
        diff
      end
      """

      assert fix(input) == input
    end

    test "Enum.sum + length added together" do
      input = """
      def run(numbers) do
        result = Enum.sum(numbers) + length(numbers)
        result
      end
      """

      assert fix(input) == input
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

      assert fix(input) == input
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

      assert fix(input) == input
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

      assert fix(input) == input
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # One bare + one inline → merged with generated variable
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes bare assignment + inline call" do
    test "bare length + inline Enum.sum — exact idx=33 pattern" do
      input = """
      def run(numbers) do
        n = length(numbers)
        div(n * (n + 1), 2) - Enum.sum(numbers)
      end
      """

      expected = """
      def run(numbers) do
        {n, sum} = Enum.reduce(numbers, {0, 0}, fn x, {c, s} -> {c + 1, s + x} end)
        div(n * (n + 1), 2) - sum
      end
      """

      assert fix(input) == expected
    end

    test "bare length + inline Enum.sum in assignment RHS" do
      input = """
      def run(numbers) do
        count = length(numbers)
        doubled_sum = Enum.sum(numbers) * 2
        {count, doubled_sum}
      end
      """

      expected = """
      def run(numbers) do
        {count, sum} = Enum.reduce(numbers, {0, 0}, fn x, {c, s} -> {c + 1, s + x} end)
        doubled_sum = sum * 2
        {count, doubled_sum}
      end
      """

      assert fix(input) == expected
    end

    test "bare Enum.sum + inline length in assignment RHS" do
      input = """
      def run(numbers) do
        half_count = div(length(numbers), 2)
        sum = Enum.sum(numbers)
        {half_count, sum}
      end
      """

      expected = """
      def run(numbers) do
        {count, sum} = Enum.reduce(numbers, {0, 0}, fn x, {c, s} -> {c + 1, s + x} end)
        half_count = div(count, 2)
        {half_count, sum}
      end
      """

      assert fix(input) == expected
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

      assert fix(input) == expected
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

      assert fix(input) == expected
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

      assert fix(input) == input
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

      assert fix(input) == input
    end

    test "field access as argument" do
      input = """
      def run(state) do
        count = length(state.numbers)
        sum = Enum.sum(state.numbers)
        {count, sum}
      end
      """

      assert fix(input) == input
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

      assert fix(input) == input
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

      assert fix(input) == input
    end
  end

  describe "does not modify already-optimal code" do
    test "no traversal functions at all" do
      input = """
      defmodule Example do
        def run(n), do: n * 2
      end
      """

      assert fix(input) == input
    end

    test "already uses Enum.min_max" do
      input = """
      def run(numbers) do
        {minimum, maximum} = Enum.min_max(numbers)
        {minimum, maximum}
      end
      """

      assert fix(input) == input
    end
  end
end
