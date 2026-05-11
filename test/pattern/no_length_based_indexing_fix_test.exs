defmodule Credence.Pattern.NoLengthBasedIndexingFixTest do
  use ExUnit.Case

  defp fix(code) do
    result = Credence.Pattern.NoLengthBasedIndexing.fix(code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC FIXES — n - K → -K
  # ═══════════════════════════════════════════════════════════════════

  describe "replaces length-based index with negative index" do
    test "single Enum.at, removes unused length line" do
      input = """
      def run(list) do
        n = length(list)
        last = Enum.at(list, n - 1)
        last
      end
      """

      expected = """
      def run(list) do
        last = Enum.at(list, -1)
        last
      end
      """

      assert fix(input) == expected
    end

    test "single Enum.at, removes unused length line without assign" do
      input = """
      def run(list) do
        n = length(list)
        Enum.at(list, n - 1)
      end
      """

      expected = """
      def run(list) do
        Enum.at(list, -1)
      end
      """

      assert fix(input) == expected
    end

    test "multiple Enum.at, removes unused length line" do
      input = """
      def run(sorted) do
        n = length(sorted)
        largest = Enum.at(sorted, n - 1)
        second = Enum.at(sorted, n - 2)
        third = Enum.at(sorted, n - 3)
        {largest, second, third}
      end
      """

      expected = """
      def run(sorted) do
        largest = Enum.at(sorted, -1)
        second = Enum.at(sorted, -2)
        third = Enum.at(sorted, -3)
        {largest, second, third}
      end
      """

      assert fix(input) == expected
    end

    test "different variable name for length binding" do
      input = """
      def run(list) do
        count = length(list)
        last = Enum.at(list, count - 1)
        last
      end
      """

      expected = """
      def run(list) do
        last = Enum.at(list, -1)
        last
      end
      """

      assert fix(input) == expected
    end

    test "Enum.count variant" do
      input = """
      def run(list) do
        n = Enum.count(list)
        last = Enum.at(list, n - 1)
        last
      end
      """

      expected = """
      def run(list) do
        last = Enum.at(list, -1)
        last
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # KEEPS LENGTH LINE — when used for other purposes
  # ═══════════════════════════════════════════════════════════════════

  describe "keeps length line when used elsewhere" do
    test "length used in arithmetic and indexing" do
      input = """
      def run(numbers) do
        n = length(numbers)
        expected = div(n * (n + 1), 2)
        last = Enum.at(numbers, n - 1)
        {expected, last}
      end
      """

      expected = """
      def run(numbers) do
        n = length(numbers)
        expected = div(n * (n + 1), 2)
        last = Enum.at(numbers, -1)
        {expected, last}
      end
      """

      assert fix(input) == expected
    end

    test "length used in condition and indexing" do
      input = """
      def run(list) do
        n = length(list)
        last = Enum.at(list, n - 1)
        if n > 0, do: last, else: nil
      end
      """

      expected = """
      def run(list) do
        n = length(list)
        last = Enum.at(list, -1)
        if n > 0, do: last, else: nil
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MIXED LITERAL AND COMPUTED INDICES
  # ═══════════════════════════════════════════════════════════════════

  describe "only fixes length-based indices" do
    test "literal indices untouched, computed fixed" do
      input = """
      def run(sorted) do
        n = length(sorted)
        first = Enum.at(sorted, 0)
        second = Enum.at(sorted, 1)
        last = Enum.at(sorted, n - 1)
        second_last = Enum.at(sorted, n - 2)
        {first, second, last, second_last}
      end
      """

      expected = """
      def run(sorted) do
        first = Enum.at(sorted, 0)
        second = Enum.at(sorted, 1)
        last = Enum.at(sorted, -1)
        second_last = Enum.at(sorted, -2)
        {first, second, last, second_last}
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # INSIDE A MODULE — full context
  # ═══════════════════════════════════════════════════════════════════

  describe "works inside a module" do
    test "exact pattern from idx=22 log" do
      input = """
      defmodule MathUtils do
        def max_product(numbers) do
          sorted = Enum.sort(numbers)
          n = length(sorted)
          smallest_first = Enum.at(sorted, 0)
          smallest_second = Enum.at(sorted, 1)
          largest = Enum.at(sorted, n - 1)
          second_largest = Enum.at(sorted, n - 2)
          third_largest = Enum.at(sorted, n - 3)
          max(smallest_first * smallest_second * largest, largest * second_largest * third_largest)
        end
      end
      """

      expected = """
      defmodule MathUtils do
        def max_product(numbers) do
          sorted = Enum.sort(numbers)
          smallest_first = Enum.at(sorted, 0)
          smallest_second = Enum.at(sorted, 1)
          largest = Enum.at(sorted, -1)
          second_largest = Enum.at(sorted, -2)
          third_largest = Enum.at(sorted, -3)
          max(smallest_first * smallest_second * largest, largest * second_largest * third_largest)
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # PRESERVES INTERVENING CODE
  # ═══════════════════════════════════════════════════════════════════

  describe "preserves surrounding code" do
    test "code between length and Enum.at" do
      input = """
      def run(list) do
        n = length(list)
        IO.puts("processing")
        last = Enum.at(list, n - 1)
        last
      end
      """

      expected = """
      def run(list) do
        IO.puts("processing")
        last = Enum.at(list, -1)
        last
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify already-negative indices" do
    test "Enum.at with negative literal" do
      input = """
      def run(list) do
        last = Enum.at(list, -1)
        second = Enum.at(list, -2)
        {last, second}
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify length on different variable" do
    test "length(a) but Enum.at(b, ...)" do
      input = """
      def run(a, b) do
        n = length(a)
        last = Enum.at(b, n - 1)
        last
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify non-literal subtraction" do
    test "variable offset" do
      input = """
      def run(list, offset) do
        n = length(list)
        val = Enum.at(list, n - offset)
        val
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify non-subtraction expressions" do
    test "n + 1" do
      input = """
      def run(list) do
        n = length(list)
        val = Enum.at(list, n + 1)
        val
      end
      """

      assert fix(input) == input
    end

    test "bare n" do
      input = """
      def run(list) do
        n = length(list)
        val = Enum.at(list, n)
        val
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify when variable is rebound" do
    test "list rebound between length and Enum.at" do
      input = """
      def run(list) do
        n = length(list)
        list = Enum.filter(list, &(&1 > 0))
        last = Enum.at(list, n - 1)
        last
      end
      """

      assert fix(input) == input
    end

    test "length variable rebound" do
      input = """
      def run(list) do
        n = length(list)
        n = n + 1
        last = Enum.at(list, n - 1)
        last
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify length used only for non-indexing" do
    test "arithmetic only" do
      input = """
      def run(numbers) do
        n = length(numbers)
        div(n * (n + 1), 2)
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify clean code" do
    test "no length or Enum.at" do
      input = """
      defmodule M do
        def run(n), do: n * 2
      end
      """

      assert fix(input) == input
    end
  end
end
