defmodule Credence.Pattern.NoMapGetSentinelFixTest do
  use ExUnit.Case

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(Credence.Pattern.NoMapGetSentinel, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # EQUALITY FIXES — sentinel literal swapped to nil (existing)
  # ═══════════════════════════════════════════════════════════════════

  describe "replaces != sentinel with != nil" do
    test "basic != -1" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if val != -1, do: val, else: :missing
      end
      """

      expected = """
      def run(map) do
        val = Map.get(map, :key)
        if val != nil, do: val, else: :missing
      end
      """

      assert fix(input) == expected
    end

    test "!== -1" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if val !== -1, do: val, else: :missing
      end
      """

      expected = """
      def run(map) do
        val = Map.get(map, :key)
        if val !== nil, do: val, else: :missing
      end
      """

      assert fix(input) == expected
    end
  end

  describe "replaces == sentinel with == nil" do
    test "basic == -1" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if val == -1, do: :missing, else: val
      end
      """

      expected = """
      def run(map) do
        val = Map.get(map, :key)
        if val == nil, do: :missing, else: val
      end
      """

      assert fix(input) == expected
    end

    test "=== -1" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if val === -1, do: :missing, else: val
      end
      """

      expected = """
      def run(map) do
        val = Map.get(map, :key)
        if val === nil, do: :missing, else: val
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # EQUALITY — compound conditions
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes equality in compound conditions" do
    test "sentinel check with and — exact pattern from idx=11" do
      input = """
      def run(char_map, grapheme, start_index) do
        last_seen = Map.get(char_map, grapheme, -1)
        if last_seen != -1 and last_seen >= start_index do
          last_seen + 1
        else
          start_index
        end
      end
      """

      expected = """
      def run(char_map, grapheme, start_index) do
        last_seen = Map.get(char_map, grapheme)
        if last_seen != nil and last_seen >= start_index do
          last_seen + 1
        else
          start_index
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # EQUALITY — flipped, different sentinels, multiple, module, intervening
  # ═══════════════════════════════════════════════════════════════════

  describe "handles sentinel on left side of equality" do
    test "-1 != val → nil != val" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if -1 != val, do: val, else: :missing
      end
      """

      expected = """
      def run(map) do
        val = Map.get(map, :key)
        if nil != val, do: val, else: :missing
      end
      """

      assert fix(input) == expected
    end

    test "-1 == val → nil == val" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if -1 == val, do: :missing, else: val
      end
      """

      expected = """
      def run(map) do
        val = Map.get(map, :key)
        if nil == val, do: :missing, else: val
      end
      """

      assert fix(input) == expected
    end
  end

  describe "handles different negative integer sentinels" do
    test "-999 sentinel" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -999)
        if val != -999, do: val, else: :default
      end
      """

      expected = """
      def run(map) do
        val = Map.get(map, :key)
        if val != nil, do: val, else: :default
      end
      """

      assert fix(input) == expected
    end

    test "-2 sentinel" do
      input = """
      def run(map) do
        idx = Map.get(map, :pos, -2)
        if idx != -2, do: idx, else: 0
      end
      """

      expected = """
      def run(map) do
        idx = Map.get(map, :pos)
        if idx != nil, do: idx, else: 0
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fixes all equality comparisons in scope" do
    test "both != and == against same sentinel" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if val != -1 do
          process(val)
        end
        if val == -1 do
          log_miss()
        end
      end
      """

      expected = """
      def run(map) do
        val = Map.get(map, :key)
        if val != nil do
          process(val)
        end
        if val == nil do
          log_miss()
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "works inside a module" do
    test "full module context" do
      input = """
      defmodule Cache do
        def lookup(cache, key) do
          val = Map.get(cache, key, -1)
          if val != -1, do: {:ok, val}, else: :miss
        end
      end
      """

      expected = """
      defmodule Cache do
        def lookup(cache, key) do
          val = Map.get(cache, key)
          if val != nil, do: {:ok, val}, else: :miss
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "preserves intervening code" do
    test "code between Map.get and equality comparison" do
      input = """
      def run(map, threshold) do
        val = Map.get(map, :key, -1)
        threshold = threshold + 1
        if val != -1 and val >= threshold do
          val
        else
          threshold
        end
      end
      """

      expected = """
      def run(map, threshold) do
        val = Map.get(map, :key)
        threshold = threshold + 1
        if val != nil and val >= threshold do
          val
        else
          threshold
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ORDERING FIXES — nil guard added (NEW)
  # ═══════════════════════════════════════════════════════════════════

  describe "wraps ordering comparison with nil guard" do
    test "var >= other_var — exact idx=32 pattern" do
      input = """
      def run(char_map, current_char, left_index) do
        previous_position = Map.get(char_map, current_char, -1)
        if previous_position >= left_index do
          previous_position + 1
        else
          left_index
        end
      end
      """

      expected = """
      def run(char_map, current_char, left_index) do
        previous_position = Map.get(char_map, current_char)
        if previous_position != nil and previous_position >= left_index do
          previous_position + 1
        else
          left_index
        end
      end
      """

      assert fix(input) == expected
    end

    test "var > other_var" do
      input = """
      def run(map, threshold) do
        val = Map.get(map, :key, -1)
        if val > threshold, do: val, else: 0
      end
      """

      expected = """
      def run(map, threshold) do
        val = Map.get(map, :key)
        if val != nil and val > threshold, do: val, else: 0
      end
      """

      assert fix(input) == expected
    end

    test "flipped: threshold <= var" do
      input = """
      def run(map, threshold) do
        val = Map.get(map, :key, -1)
        if threshold <= val, do: val, else: 0
      end
      """

      expected = """
      def run(map, threshold) do
        val = Map.get(map, :key)
        if val != nil and threshold <= val, do: val, else: 0
      end
      """

      assert fix(input) == expected
    end

    test "var >= 0" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if val >= 0, do: val, else: :missing
      end
      """

      expected = """
      def run(map) do
        val = Map.get(map, :key)
        if val != nil and val >= 0, do: val, else: :missing
      end
      """

      assert fix(input) == expected
    end

    test "multiple ordering comparisons" do
      input = """
      def run(map, low, high) do
        val = Map.get(map, :key, -1)
        if val >= low and val < high do
          val
        else
          0
        end
      end
      """

      expected = """
      def run(map, low, high) do
        val = Map.get(map, :key)
        if val != nil and val >= low and val != nil and val < high do
          val
        else
          0
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify non-negative defaults" do
    test "default is 0 with equality" do
      input = """
      def run(map) do
        count = Map.get(map, :count, 0)
        if count != 0, do: count, else: :none
      end
      """

      assert fix(input) == input
    end

    test "default is 0 with ordering" do
      input = """
      def run(map, threshold) do
        count = Map.get(map, :count, 0)
        if count >= threshold, do: count, else: :none
      end
      """

      assert fix(input) == input
    end

    test "default is positive integer" do
      input = """
      def run(map) do
        val = Map.get(map, :key, 1)
        if val != 1, do: val, else: :default
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify non-integer defaults" do
    test "default is atom" do
      input = """
      def run(map) do
        val = Map.get(map, :key, :not_found)
        if val != :not_found, do: val, else: :missing
      end
      """

      assert fix(input) == input
    end

    test "default is false" do
      input = """
      def run(map) do
        val = Map.get(map, :enabled, false)
        if val != false, do: :on, else: :off
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify when no comparison" do
    test "sentinel used in arithmetic only" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        val + 1
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify when variable is rebound" do
    test "rebinding between Map.get and equality comparison" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        val = transform(val)
        if val != -1, do: val, else: :missing
      end
      """

      assert fix(input) == input
    end

    test "rebinding between Map.get and ordering comparison" do
      input = """
      def run(map, threshold) do
        val = Map.get(map, :key, -1)
        val = transform(val)
        if val >= threshold, do: val, else: 0
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify different scopes" do
    test "Map.get and comparison in different functions" do
      input = """
      defmodule M do
        def get_val(map), do: Map.get(map, :key, -1)

        def check(val) do
          if val != -1 do
            val
          else
            :missing
          end
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify comparison against different value" do
    test "sentinel -1 but equality against -2" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if val != -2, do: val, else: :missing
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify ordering comparison against sentinel literal" do
    test "val > -1 — directly against sentinel" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if val > -1, do: val, else: :missing
      end
      """

      assert fix(input) == input
    end

    test "val >= -1 — directly against sentinel" do
      input = """
      def run(map) do
        val = Map.get(map, :key, -1)
        if val >= -1, do: val, else: :missing
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify already-clean code" do
    test "two-arg Map.get with nil check" do
      input = """
      def run(map) do
        val = Map.get(map, :key)
        if val != nil, do: val, else: :missing
      end
      """

      assert fix(input) == input
    end

    test "no Map.get at all" do
      input = """
      defmodule M do
        def run(n), do: n * 2
      end
      """

      assert fix(input) == input
    end
  end
end
