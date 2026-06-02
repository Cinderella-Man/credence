defmodule Credence.Pattern.NoSingleUseBindingFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoSingleUseBinding

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(NoSingleUseBinding, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — inlines single-use binding
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes single-use binding in comparison" do
    test "inlines GCD comparison" do
      input = """
      def run(a, b) do
        gcd = Integer.gcd(a, b)
        gcd == 1
      end
      """

      expected = """
      def run(a, b) do
        Integer.gcd(a, b) == 1
      end
      """

      assert fix(input) == expected
    end

    test "inlines greater-than comparison" do
      input = """
      def run(x) do
        val = compute(x)
        val > 0
      end
      """

      expected = """
      def run(x) do
        compute(x) > 0
      end
      """

      assert fix(input) == expected
    end

    test "inlines not-equal comparison" do
      input = """
      def run(x) do
        result = process(x)
        result != :error
      end
      """

      expected = """
      def run(x) do
        process(x) != :error
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fixes single-use binding in boolean expression" do
    test "inlines boolean and" do
      input = """
      def run(x) do
        val = compute(x)
        val > 0 and other_check(x)
      end
      """

      expected = """
      def run(x) do
        compute(x) > 0 and other_check(x)
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — inlines simple variable alias
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes simple variable alias" do
    test "inlines alias used in function call" do
      input = """
      def run(list, char) do
        target = char
        do_count(list, target, 0, 0)
      end
      """

      expected = """
      def run(list, char) do
        do_count(list, char, 0, 0)
      end
      """

      assert fix(input) == expected
    end

    test "inlines alias used in arithmetic" do
      input = """
      def run(x) do
        y = x
        y + 1
      end
      """

      expected = """
      def run(x) do
        x + 1
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — handles multiple single-use bindings across functions
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes single-use bindings in multiple functions" do
    test "two functions each with a single-use binding" do
      input = """
      defmodule M do
        def run(a, b) do
          gcd = Integer.gcd(a, b)
          gcd == 1
        end

        def check(x) do
          val = compute(x)
          val > 0
        end
      end
      """

      expected = """
      defmodule M do
        def run(a, b) do
          Integer.gcd(a, b) == 1
        end

        def check(x) do
          compute(x) > 0
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO FIX — code that should not be changed
  # ═══════════════════════════════════════════════════════════════════

  describe "does not fix when variable is used multiple times" do
    test "used twice in boolean and" do
      input = """
      def run(a, b) do
        gcd = Integer.gcd(a, b)
        gcd > 0 and gcd < 10
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not fix comparison group feeding into boolean" do
    test "two comparison bindings combined with or" do
      input = """
      def run(shorter, longer) do
        replacement_ok = shorter == longer
        insertion_ok = shorter == tl(longer)
        replacement_ok or insertion_ok
      end
      """

      assert fix(input) == input
    end

    test "two comparison bindings combined with and" do
      input = """
      def run(x, threshold) do
        above_min = x > 0
        below_max = x < threshold
        above_min and below_max
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not fix non-operator expressions" do
    test "function call argument" do
      input = """
      def run(list) do
        count = Enum.count(list)
        IO.puts(count)
      end
      """

      assert fix(input) == input
    end

    test "pipe expression" do
      input = """
      def run(list) do
        result = Enum.map(list, &process/1)
        result |> Enum.filter(&valid?/1)
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not fix control-flow expressions" do
    test "if expression" do
      input = """
      def run(x) do
        result = compute(x)
        if result > 0, do: :positive, else: :non_positive
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not fix variable-only next statement" do
    test "assign and return" do
      input = """
      def run(a, b) do
        gcd = Integer.gcd(a, b)
        gcd
      end
      """

      assert fix(input) == input
    end
  end
end
