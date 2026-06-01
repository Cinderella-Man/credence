defmodule Credence.Pattern.NoIfSubtractionForMaxFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoIfSubtractionForMax

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(NoIfSubtractionForMax, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC FIXES
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites if a > b, do: a - b, else: 0 to max(0, a - b)" do
    test "basic inline form with >" do
      input = """
      def run(x, y) do
        if x > y, do: x - y, else: 0
      end
      """

      expected = """
      def run(x, y) do
        max(0, x - y)
      end
      """

      assert fix(input) == expected
    end

    test "basic inline form with >=" do
      input = """
      def run(x, y) do
        if x >= y, do: x - y, else: 0
      end
      """

      expected = """
      def run(x, y) do
        max(0, x - y)
      end
      """

      assert fix(input) == expected
    end

    test "block form" do
      input = """
      def run(x, y) do
        if x > y do
          x - y
        else
          0
        end
      end
      """

      expected = """
      def run(x, y) do
        max(0, x - y)
      end
      """

      assert fix(input) == expected
    end

    test "assigned to variable" do
      input = """
      def run(new_max_left, left_height) do
        water = if new_max_left > left_height, do: new_max_left - left_height, else: 0
        water
      end
      """

      expected = """
      def run(new_max_left, left_height) do
        water = max(0, new_max_left - left_height)
        water
      end
      """

      assert fix(input) == expected
    end

    test "nested inside another if" do
      input = """
      def run(x, y, a, b) do
        if x > y do
          val = if a > b, do: a - b, else: 0
          val
        else
          0
        end
      end
      """

      expected = """
      def run(x, y, a, b) do
        if x > y do
          val = max(0, a - b)
          val
        else
          0
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "does not modify code that doesn't match" do
    test "else is not 0" do
      input = """
      def run(x, y) do
        if x > y, do: x - y, else: 1
      end
      """

      assert fix(input) == input
    end

    test "operands don't match" do
      input = """
      def run(x, y, z) do
        if x > y, do: x - z, else: 0
      end
      """

      assert fix(input) == input
    end

    test "already uses max" do
      input = """
      def run(x, y) do
        max(0, x - y)
      end
      """

      assert fix(input) == input
    end
  end
end
