defmodule Credence.Pattern.NoUnlessElseFixTest do
  use ExUnit.Case

  defp fix(code) do
    result = Credence.Pattern.NoUnlessElse.fix(code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC FIXES — unless...else → if...else with swapped bodies
  # ═══════════════════════════════════════════════════════════════════

  describe "swaps unless...else to if...else" do
    test "basic block form" do
      input = """
      def run(x) do
        unless x > 0 do
          :negative
        else
          :positive
        end
      end
      """

      expected = """
      def run(x) do
        if x > 0 do
          :positive
        else
          :negative
        end
      end
      """

      assert fix(input) == expected
    end

    test "inline form" do
      input = """
      def run(x) do
        unless x > 0, do: :negative, else: :positive
      end
      """

      expected = """
      def run(x) do
        if x > 0, do: :positive, else: :negative
      end
      """

      assert fix(input) == expected
    end

    test "multi-line bodies" do
      input = """
      def run(list) do
        unless Enum.empty?(list) do
          first = hd(list)
          process(first)
        else
          log(:empty)
          :default
        end
      end
      """

      expected = """
      def run(list) do
        if Enum.empty?(list) do
          log(:empty)
          :default
        else
          first = hd(list)
          process(first)
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CONDITION PRESERVED — no negation, no manipulation
  # ═══════════════════════════════════════════════════════════════════

  describe "preserves complex conditions as-is" do
    test "and condition" do
      input = """
      def run(x, y) do
        unless x > 0 and y > 0 do
          :invalid
        else
          x + y
        end
      end
      """

      expected = """
      def run(x, y) do
        if x > 0 and y > 0 do
          x + y
        else
          :invalid
        end
      end
      """

      assert fix(input) == expected
    end

    test "function call condition" do
      input = """
      def run(set, value) do
        unless MapSet.member?(set, value) do
          :missing
        else
          :found
        end
      end
      """

      expected = """
      def run(set, value) do
        if MapSet.member?(set, value) do
          :found
        else
          :missing
        end
      end
      """

      assert fix(input) == expected
    end

    test "negated condition" do
      input = """
      def run(x) do
        unless not is_nil(x) do
          :was_nil
        else
          x
        end
      end
      """

      expected = """
      def run(x) do
        if not is_nil(x) do
          x
        else
          :was_nil
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CONTEXT — inside modules, with surrounding code
  # ═══════════════════════════════════════════════════════════════════

  describe "works in different contexts" do
    test "inside a module" do
      input = """
      defmodule Example do
        def run(x) do
          unless x == 0 do
            div(100, x)
          else
            :zero
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def run(x) do
          if x == 0 do
            :zero
          else
            div(100, x)
          end
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves surrounding code" do
      input = """
      def run(x) do
        before = setup()
        unless x > 0 do
          :negative
        else
          :positive
        end
      end
      """

      expected = """
      def run(x) do
        before = setup()

        if x > 0 do
          :positive
        else
          :negative
        end
      end
      """

      assert fix(input) == expected
    end

    test "used as expression assignment" do
      input = """
      def run(x) do
        result = unless x > 0 do
          :negative
        else
          :positive
        end
        result
      end
      """

      expected = """
      def run(x) do
        result =
          if x > 0 do
            :positive
          else
            :negative
          end

        result
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # EXACT LOG PATTERN — idx=43
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes the exact pattern from logs" do
    test "idx=43 — unless inside Enum.reduce" do
      input = """
      def longest_consecutive(numbers) do
        number_set = MapSet.new(numbers)

        Enum.reduce(number_set, 0, fn candidate_number, max_length ->
          unless MapSet.member?(number_set, candidate_number - 1) do
            current_length = count_sequence(candidate_number, number_set, 1)
            max(max_length, current_length)
          else
            max_length
          end
        end)
      end
      """

      expected = """
      def longest_consecutive(numbers) do
        number_set = MapSet.new(numbers)

        Enum.reduce(number_set, 0, fn candidate_number, max_length ->
          if MapSet.member?(number_set, candidate_number - 1) do
            max_length
          else
            current_length = count_sequence(candidate_number, number_set, 1)
            max(max_length, current_length)
          end
        end)
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes multiple occurrences" do
    test "two unless...else in same function" do
      input = """
      def run(x, y) do
        a = unless x > 0, do: :neg, else: :pos
        b = unless y > 0, do: :neg, else: :pos
        {a, b}
      end
      """

      expected = """
      def run(x, y) do
        a = if x > 0, do: :pos, else: :neg
        b = if y > 0, do: :pos, else: :neg
        {a, b}
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify unless without else" do
    test "bare unless block" do
      input = """
      def run(x) do
        unless x > 0 do
          log(:negative)
        end
      end
      """

      assert fix(input) == input
    end

    test "bare unless inline" do
      input = """
      def run(x) do
        unless x > 0, do: log(:negative)
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify if statements" do
    test "if with else" do
      input = """
      def run(x) do
        if x > 0 do
          :positive
        else
          :negative
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify code without unless" do
    test "plain function" do
      input = """
      defmodule M do
        def run(x), do: x * 2
      end
      """

      assert fix(input) == input
    end
  end
end
