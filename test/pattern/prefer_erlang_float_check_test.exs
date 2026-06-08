defmodule Credence.Pattern.PreferErlangFloatCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferErlangFloat

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLY BY 1.0 — bare variable (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "var * 1.0" do
    test "flags n * 1.0" do
      assert flagged?(PreferErlangFloat, """
             n * 1.0
             """)
    end

    test "flags 1.0 * n" do
      assert flagged?(PreferErlangFloat, """
             1.0 * n
             """)
    end

    test "flags with longer variable name" do
      assert flagged?(PreferErlangFloat, """
             my_value * 1.0
             """)
    end

    test "flags underscore-prefixed variable" do
      assert flagged?(PreferErlangFloat, """
             _n * 1.0
             """)
    end

    test "flags self-assignment var = var * 1.0" do
      assert flagged?(PreferErlangFloat, """
             count = count * 1.0
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DIVIDE BY 1.0 — bare variable (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "var / 1.0" do
    test "flags n / 1.0" do
      assert flagged?(PreferErlangFloat, """
             n / 1.0
             """)
    end

    test "flags self-assignment n = n / 1.0" do
      assert flagged?(PreferErlangFloat, """
             n = n / 1.0
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ADD 0.0 — bare variable (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "var + 0.0" do
    test "flags n + 0.0" do
      assert flagged?(PreferErlangFloat, """
             n + 0.0
             """)
    end

    test "flags 0.0 + n" do
      assert flagged?(PreferErlangFloat, """
             0.0 + n
             """)
    end

    test "flags self-assignment n = n + 0.0" do
      assert flagged?(PreferErlangFloat, """
             n = n + 0.0
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SUBTRACT 0.0 — bare variable (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "var - 0.0" do
    test "flags n - 0.0" do
      assert flagged?(PreferErlangFloat, """
             n - 0.0
             """)
    end

    test "flags self-assignment n = n - 0.0" do
      assert flagged?(PreferErlangFloat, """
             n = n - 0.0
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REALISTIC CONTEXT (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "realistic function contexts" do
    test "flags in one-liner def" do
      assert flagged?(PreferErlangFloat, """
             def to_float(n), do: n * 1.0
             """)
    end

    test "flags in defp with guard" do
      assert flagged?(PreferErlangFloat, """
             defp to_float(n) when is_integer(n), do: n * 1.0
             """)
    end

    test "flags bare var at end of multi-line body" do
      code = """
      def process(data) do
        result = calculate(data)
        result * 1.0
      end
      """

      assert flagged?(PreferErlangFloat, code)
    end

    test "flags in case branch" do
      code = """
      case type do
        :int -> n * 1.0
        :float -> n
      end
      """

      assert flagged?(PreferErlangFloat, code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "multiple hits" do
    test "flags two bare-var coercions in same module" do
      code = """
      defmodule Coerce do
        def to_float(n), do: n * 1.0
        def ensure_float(x), do: x + 0.0
      end
      """

      assert length(check(PreferErlangFloat, code)) == 2
    end

    test "flags mixed operators" do
      code = """
      defmodule Coerce do
        def mul(n), do: n * 1.0
        def div(n), do: n / 1.0
        def add(n), do: n + 0.0
      end
      """

      assert length(check(PreferErlangFloat, code)) == 3
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MIXED BARE + NON-BARE ON SAME LINE
  # ═══════════════════════════════════════════════════════════════════

  describe "mixed bare and non-bare on same line (both flagged after merge)" do
    test "flags bare var and function call on same line" do
      assert flagged?(PreferErlangFloat, """
             {n * 1.0, Enum.sum(xs) * 1.0}
             """)
    end

    test "counts both bare-var and non-bare hits" do
      assert length(
               check(PreferErlangFloat, """
               {n * 1.0, Enum.sum(xs) * 1.0}
               """)
             ) == 2
    end

    test "flags all three when two bare + one non-bare" do
      assert length(
               check(PreferErlangFloat, """
               {n * 1.0, Enum.sum(xs) * 1.0, m + 0.0}
               """)
             ) == 3
    end

    test "flags bare var with leading identity plus non-bare" do
      assert length(
               check(PreferErlangFloat, """
               {1.0 * n, Enum.sum(xs) * 1.0}
               """)
             ) == 2
    end

    test "in function context" do
      assert length(
               check(PreferErlangFloat, """
               def foo(n, xs), do: {n * 1.0, Enum.sum(xs) * 1.0}
               """)
             ) ==
               2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGGED — compound / non-bare operands (merged in from the old
  # NoIdentityFloatCoercion; now WRAPPED in :erlang.float, not removed)
  # ═══════════════════════════════════════════════════════════════════

  describe "flags non-bare operands" do
    test "function call * 1.0" do
      assert flagged?(PreferErlangFloat, """
             Enum.at(list, 0) * 1.0
             """)
    end

    test "compound expression * 1.0" do
      assert flagged?(PreferErlangFloat, """
             (a + b) * 1.0
             """)
    end

    test "1.0 * function call" do
      assert flagged?(PreferErlangFloat, """
             1.0 * Enum.sum(list)
             """)
    end

    test "function call / 1.0" do
      assert flagged?(PreferErlangFloat, """
             Enum.count(list) / 1.0
             """)
    end

    test "function call + 0.0" do
      assert flagged?(PreferErlangFloat, """
             Enum.sum(list) + 0.0
             """)
    end

    test "tuple access * 1.0" do
      assert flagged?(PreferErlangFloat, """
             elem(pair, 0) * 1.0
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MUST NOT FLAG — real arithmetic
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag real arithmetic" do
    test "n * 2.0" do
      assert clean?(PreferErlangFloat, """
             n * 2.0
             """)
    end

    test "n * 1 (integer)" do
      assert clean?(PreferErlangFloat, """
             n * 1
             """)
    end

    test "n * 1.05" do
      assert clean?(PreferErlangFloat, """
             n * 1.05
             """)
    end

    test "n / 2.0" do
      assert clean?(PreferErlangFloat, """
             n / 2.0
             """)
    end

    test "n / 1 (integer)" do
      assert clean?(PreferErlangFloat, """
             n / 1
             """)
    end

    test "n + 1.0" do
      assert clean?(PreferErlangFloat, """
             n + 1.0
             """)
    end

    test "n - 1.0" do
      assert clean?(PreferErlangFloat, """
             n - 1.0
             """)
    end

    test "n + 0 (integer)" do
      assert clean?(PreferErlangFloat, """
             n + 0
             """)
    end

    test "n - 0 (integer)" do
      assert clean?(PreferErlangFloat, """
             n - 0
             """)
    end

    test "n * 1.0e5 (scientific notation)" do
      assert clean?(PreferErlangFloat, """
             n * 1.0e5
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MUST NOT FLAG — negation
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag negation" do
    test "0.0 - n (negation, not identity)" do
      assert clean?(PreferErlangFloat, """
             0.0 - n
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MUST NOT FLAG — already converted
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag already-correct code" do
    test ":erlang.float(n)" do
      assert clean?(PreferErlangFloat, """
             :erlang.float(n)
             """)
    end

    test "no coercion at all" do
      assert clean?(PreferErlangFloat, """
             def run(n), do: n + 1
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # META
  # ═══════════════════════════════════════════════════════════════════
end
