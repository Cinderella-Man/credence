defmodule Credence.Pattern.NoIfTrueFalseFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoIfTrueFalse

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(NoIfTrueFalse, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC FIXES — if...true...else...false → condition
  # ═══════════════════════════════════════════════════════════════════

  describe "redundant boolean if to condition" do
    test "basic block form" do
      input = """
      def check(x) do
        if x > 0 do
          true
        else
          false
        end
      end
      """

      expected = """
      def check(x) do
        x > 0
      end
      """

      assert fix(input) == expected
    end

    test "with complex condition" do
      input = """
      def check(parts) do
        if match?([_, _, _, _], parts) and Enum.all?(parts, &valid_octet?/1) do
          true
        else
          false
        end
      end
      """

      expected = """
      def check(parts) do
        match?([_, _, _, _], parts) and Enum.all?(parts, &valid_octet?/1)
      end
      """

      assert fix(input) == expected
    end

    test "inline form" do
      input = """
      def check(x) do
        if x > 0, do: true, else: false
      end
      """

      expected = """
      def check(x) do
        x > 0
      end
      """

      assert fix(input) == expected
    end

    test "reversed branches (false/true) — negated" do
      input = """
      def check(x) do
        if x > 0 do
          false
        else
          true
        end
      end
      """

      expected = """
      def check(x) do
        x <= 0
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # GENERALISED FIXES — if...comparison...else...false → condition and expr
  # ═══════════════════════════════════════════════════════════════════

  describe "redundant boolean if with comparison to condition and expr" do
    test "comparison in do body" do
      input = """
      def check(x, y) do
        if x > 0 do
          y == 1
        else
          false
        end
      end
      """

      expected = """
      def check(x, y) do
        x > 0 and y == 1
      end
      """

      assert fix(input) == expected
    end

    test "boolean and in do body" do
      input = """
      def check(x, a, b) do
        if x > 0 do
          a and b
        else
          false
        end
      end
      """

      expected = """
      def check(x, a, b) do
        x > 0 and (a and b)
      end
      """

      assert fix(input) == expected
    end

    test "not expression in do body" do
      input = """
      def check(x, y) do
        if x > 0 do
          not y
        else
          false
        end
      end
      """

      expected = """
      def check(x, y) do
        x > 0 and not y
      end
      """

      assert fix(input) == expected
    end

    test "inline comparison form" do
      input = """
      def check(x, y) do
        if x > 0, do: y == 1, else: false
      end
      """

      expected = """
      def check(x, y) do
        x > 0 and y == 1
      end
      """

      assert fix(input) == expected
    end

    test "comparison in do body with else true" do
      input = """
      def run(x, y) do
        if x > 0 do
          y == 1
        else
          true
        end
      end
      """

      expected = """
      def run(x, y) do
        x <= 0 or y == 1
      end
      """

      assert fix(input) == expected
    end

    test "false in do body with comparison in else" do
      input = """
      def run(x, y) do
        if x > 0 do
          false
        else
          y == 1
        end
      end
      """

      expected = """
      def run(x, y) do
        x <= 0 and y == 1
      end
      """

      assert fix(input) == expected
    end

    test "true in do body with comparison in else" do
      input = """
      def run(x, y) do
        if x > 0 do
          true
        else
          y == 1
        end
      end
      """

      expected = """
      def run(x, y) do
        x > 0 or y == 1
      end
      """

      assert fix(input) == expected
    end

    test "true in do body with Enum.all? in else" do
      input = """
      def check(list) do
        if list == [] do
          true
        else
          Enum.all?(list, &valid?/1)
        end
      end
      """

      expected = """
      def check(list) do
        list == [] or Enum.all?(list, &valid?/1)
      end
      """

      assert fix(input) == expected
    end

    test "Enum.any? in do body with else false" do
      input = """
      def check(list) do
        if list == [] do
          Enum.any?(list, &positive?/1)
        else
          false
        end
      end
      """

      expected = """
      def check(list) do
        list == [] and Enum.any?(list, &positive?/1)
      end
      """

      assert fix(input) == expected
    end

    test "is_nil in do body with else false" do
      input = """
      def check(x) do
        if x > 0 do
          is_nil(x)
        else
          false
        end
      end
      """

      expected = """
      def check(x) do
        x > 0 and is_nil(x)
      end
      """

      assert fix(input) == expected
    end

    test "match? in do body with else false" do
      input = """
      def check(x) do
        if x > 0 do
          match?({:ok, _}, x)
        else
          false
        end
      end
      """

      expected = """
      def check(x) do
        x > 0 and match?({:ok, _}, x)
      end
      """

      assert fix(input) == expected
    end

    test "function call in do body with else false — NOT fixed" do
      input = """
      def run(x) do
        if x > 0 do
          some_check(x)
        else
          false
        end
      end
      """

      assert fix(input) == input
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CONTEXT — inside modules, with surrounding code
  # ═══════════════════════════════════════════════════════════════════

  describe "works in different contexts" do
    test "inside a module" do
      input = """
      defmodule Validator do
        def valid?(items) do
          if length(items) == 4 do
            true
          else
            false
          end
        end
      end
      """

      expected = """
      defmodule Validator do
        def valid?(items) do
          length(items) == 4
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves surrounding code" do
      input = """
      def run(x) do
        before = setup()
        if x > 0 do
          true
        else
          false
        end
      end
      """

      expected = """
      def run(x) do
        before = setup()
        x > 0
      end
      """

      assert fix(input) == expected
    end

    test "used as expression assignment" do
      input = """
      def run(x) do
        result = if x > 0 do
          true
        else
          false
        end
        result
      end
      """

      expected = """
      def run(x) do
        result = x > 0
        result
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NESTED BOOLEAN IFS — leap year pattern
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes nested boolean ifs" do
    test "leap year pattern" do
      input = """
      def check_leap_year(year) do
        rem_four = rem(year, 4)
        rem_hundred = rem(year, 100)
        rem_four_hundred = rem(year, 400)

        if rem_four == 0 do
          if rem_hundred == 0 do
            rem_four_hundred == 0
          else
            true
          end
        else
          false
        end
      end
      """

      expected = """
      def check_leap_year(year) do
        rem_four = rem(year, 4)
        rem_hundred = rem(year, 100)
        rem_four_hundred = rem(year, 400)

        rem_four == 0 and (rem_hundred != 0 or rem_four_hundred == 0)
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # EXACT LOG PATTERN — idx=51247 check_valid_ip
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes the exact pattern from logs" do
    test "idx=51247 — check_valid_ip" do
      input = """
      def check_valid_ip(ip_string) do
        parts = String.split(ip_string, ".")

        if match?([_, _, _, _], parts) and Enum.all?(parts, &valid_octet?/1) do
          true
        else
          false
        end
      end
      """

      expected = """
      def check_valid_ip(ip_string) do
        parts = String.split(ip_string, ".")

        match?([_, _, _, _], parts) and Enum.all?(parts, &valid_octet?/1)
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # COMPARISON NEGATION — not (a != b) → a == b
  # ═══════════════════════════════════════════════════════════════════

  describe "simplifies negated comparisons using complement operator" do
    test "not (a != b) becomes a == b" do
      input = """
      def counts_match?(counts1, counts2) do
        if Map.keys(counts1) != Map.keys(counts2) do
          false
        else
          Enum.all?(counts1, fn {char, count} ->
            Map.get(counts2, char) == count
          end)
        end
      end
      """

      expected = """
      def counts_match?(counts1, counts2) do
        Map.keys(counts1) == Map.keys(counts2) and
          Enum.all?(counts1, fn {char, count} ->
            Map.get(counts2, char) == count
          end)
      end
      """

      assert fix(input) == expected
    end

    test "not (a == b) becomes a != b" do
      input = """
      def check(x, y) do
        if x == y do
          false
        else
          true
        end
      end
      """

      expected = """
      def check(x, y) do
        x != y
      end
      """

      assert fix(input) == expected
    end

    test "not (a < b) becomes a >= b" do
      input = """
      def check(x, y) do
        if x < y do
          false
        else
          true
        end
      end
      """

      expected = """
      def check(x, y) do
        x >= y
      end
      """

      assert fix(input) == expected
    end

    test "not (a === b) becomes a !== b" do
      input = """
      def check(x, y) do
        if x === y do
          false
        else
          true
        end
      end
      """

      expected = """
      def check(x, y) do
        x !== y
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes multiple occurrences" do
    test "two redundant ifs in same function" do
      input = """
      def run(x, y) do
        a = if x > 0 do
          true
        else
          false
        end
        b = if y > 0 do
          true
        else
          false
        end
        {a, b}
      end
      """

      expected = """
      def run(x, y) do
        a = x > 0
        b = y > 0
        {a, b}
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify if with non-boolean returns" do
    test "if with symbol returns" do
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

    test "if with computed returns" do
      input = """
      def run(x) do
        if x > 0 do
          x * 2
        else
          0
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify if without else" do
    test "bare if block" do
      input = """
      def run(x) do
        if x > 0 do
          IO.puts("positive")
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify code without if" do
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
