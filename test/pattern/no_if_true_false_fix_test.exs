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

    test "reversed branches (false/true) — NOT fixed, would need negation" do
      input = """
      def check(x) do
        if x > 0 do
          false
        else
          true
        end
      end
      """

      assert fix(input) == input
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

    test "comparison in do body with non-false else — NOT fixed" do
      input = """
      def run(x, y) do
        if x > 0 do
          y == 1
        else
          true
        end
      end
      """

      assert fix(input) == input
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
