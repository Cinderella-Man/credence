defmodule Credence.Rule.NoRedundantNegatedGuardTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoRedundantNegatedGuard.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoRedundantNegatedGuard.fix(code, [])
  end

  describe "NoRedundantNegatedGuard" do
    # ── Positive cases (should flag) ────────────────────────────

    test "detects when == followed by != on same variables" do
      code = """
      defmodule Bad do
        defp compare([v1 | t1], [v2 | t2]) when v1 == v2, do: compare(t1, t2)
        defp compare([v1 | _], [v2 |_ ]) when v1 != v2, do: v1
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_redundant_negated_guard
      assert issue.message =~ "Redundant"
      assert issue.message =~ "!="
    end

    test "detects when === followed by !== on same variables" do
      code = """
      defmodule Bad do
        defp match(a, b) when a === b, do: :equal
        defp match(a, b) when a !== b, do: :not_equal
      end
      """

      [issue] = check(code)
      assert issue.message =~ "!=="
      assert issue.message =~ "==="
    end

    test "detects in def (not just defp)" do
      code = """
      defmodule Bad do
        def compare(x, y) when x == y, do: :same
        def compare(x, y) when x != y, do: :different
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_redundant_negated_guard
    end

    test "detects the find_missing pattern" do
      code = """
      defmodule Bad do
        defp compare_lists([value1 | rest1], [value2 | rest2]) when value1 == value2,
          do: compare_lists(rest1, rest2)
        defp compare_lists([missing_value | _rest1], [val2 |_ rest2]) when missing_value != val2,
          do: missing_value
      end
      """

      # Won't match because variable names differ (value1 vs missing_value)
      assert check(code) == []
    end

    test "detects when variable names match across clauses" do
      code = """
      defmodule Bad do
        defp compare_lists([val | rest1], [val2 | rest2]) when val == val2,
          do: compare_lists(rest1, rest2)
        defp compare_lists([val | _], [val2 |_ ]) when val != val2,
          do: val
      end
      """

      [issue] = check(code)
      assert issue.message =~ "!="
    end

    test "detects in a longer function with multiple clauses" do
      code = """
      defmodule Bad do
        defp process([h | _], []), do: h
        defp process([a | t1], [b | t2]) when a == b, do: process(t1, t2)
        defp process([a | _], [b |_ ]) when a != b, do: a
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Redundant"
    end

    # ── Negative cases (should NOT flag) ────────────────────────

    test "does not flag unrelated guards" do
      code = """
      defmodule Good do
        def process(x) when x > 0, do: :positive
        def process(x) when x < 0, do: :negative
        def process(0), do: :zero
      end
      """

      assert check(code) == []
    end

    test "does not flag clause without guard following equality guard" do
      code = """
      defmodule Good do
        defp walk([a | t1], [b | t2]) when a == b, do: walk(t1, t2)
        defp walk([missing | _],_ ), do: missing
      end
      """

      assert check(code) == []
    end

    test "does not flag negated guard without preceding equality" do
      code = """
      defmodule Good do
        defp compare([a | _], [b |_ ]) when a != b, do: a
        defp compare([_ | t1], [_ | t2]), do: compare(t1, t2)
      end
      """

      assert check(code) == []
    end

    test "does not flag different variable names in guards" do
      code = """
      defmodule Good do
        defp check(a, b) when a == b, do: :equal
        defp check(c, d) when c != d, do: :not_equal
      end
      """

      # c != d is on different vars than a == b
      # The rule compares by name, so no match → no flag
      assert check(code) == []
    end

    test "does not flag compound guards" do
      code = """
      defmodule Good do
        def foo(a, b) when a == b, do: :equal
        def foo(a, b) when a != b and a > 0, do: :positive_unequal
      end
      """

      # Compound guard — the != is part of a larger expression
      assert check(code) == []
    end

    test "does not flag pattern matching (correct approach)" do
      code = """
      defmodule Good do
        defp compare([val | t1], [val | t2]), do: compare(t1, t2)
        defp compare([missing | _],_ ), do: missing
      end
      """

      assert check(code) == []
    end

    test "does not flag single-clause functions" do
      code = """
      defmodule Good do
        def not_equal?(a, b) when a != b, do: true
      end
      """

      assert check(code) == []
    end

    test "does not flag different function names" do
      code = """
      defmodule Good do
        def equal(a, b) when a == b, do: true
        def not_equal(a, b) when a != b, do: true
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    # ── Fix: removes redundant negated guard ────────────────────

    test "removes != guard when preceded by == guard" do
      code = """
      defmodule Bad do
        defp compare([v1 | t1], [v2 | t2]) when v1 == v2, do: compare(t1, t2)
        defp compare([v1 | _], [v2 |_ ]) when v1 != v2, do: v1
      end
      """

      fixed = fix(code)
      assert fixed =~ "defp compare([v1 | t1], [v2 | t2]) when v1 == v2"
      assert fixed =~ "defp compare([v1 | _], [v2"
      assert fixed =~ "do: v1"
      refute fixed =~ "when v1 != v2"
    end

    test "removes !== guard when preceded by === guard" do
      code = """
      defmodule Bad do
        defp match(a, b) when a === b, do: :equal
        defp match(a, b) when a !== b, do: :not_equal
      end
      """

      fixed = fix(code)
      assert fixed =~ "defp match(a, b) when a === b"
      assert fixed =~ "defp match(a, b), do: :not_equal"
      refute fixed =~ "!=="
    end

    test "removes != guard in def (not just defp)" do
      code = """
      defmodule Bad do
        def compare(x, y) when x == y, do: :same
        def compare(x, y) when x != y, do: :different
      end
      """

      fixed = fix(code)
      assert fixed =~ "def compare(x, y) when x == y"
      assert fixed =~ "def compare(x, y), do: :different"
      refute fixed =~ "when x != y"
    end

    test "removes guard in longer function with multiple clauses" do
      code = """
      defmodule Bad do
        defp process([h | _], []), do: h
        defp process([a | t1], [b | t2]) when a == b, do: process(t1, t2)
        defp process([a | _], [b |_ ]) when a != b, do: a
      end
      """

      fixed = fix(code)
      assert fixed =~ "defp process([h | _], []), do: h"
      assert fixed =~ "defp process([a | t1], [b | t2]) when a == b"
      assert fixed =~ "defp process([a | _], [b"
      assert fixed =~ "do: a"
      refute fixed =~ "when a != b"
    end

    test "handles multi-line guard clause" do
      code = """
      defmodule Bad do
        defp compare([v1 | t1], [v2 | t2])
            when v1 == v2,
            do: compare(t1, t2)

        defp compare([v1 | _], [v2 |_ ])
            when v1 != v2,
            do: v1
      end
      """

      fixed = fix(code)
      assert fixed =~ "when v1 == v2"
      refute fixed =~ "when v1 != v2"
      assert fixed =~ "do: v1"
    end

    # ── Fix: preserves code without redundant guards ────────────

    test "preserves code with no issues" do
      code = """
      defmodule Good do
        def process(x) when x > 0, do: :positive
        def process(x) when x < 0, do: :negative
        def process(0), do: :zero
      end
      """

      assert fix(code) == code
    end

    test "preserves clause without guard following equality guard" do
      code = """
      defmodule Good do
        defp walk([a | t1], [b | t2]) when a == b, do: walk(t1, t2)
        defp walk([missing | _], _), do: missing
      end
      """

      assert fix(code) == code
    end

    test "preserves negated guard without preceding equality" do
      code = """
      defmodule Good do
        defp compare([a | _], [b | _]) when a != b, do: a
        defp compare([_ | t1], [_ | t2]), do: compare(t1, t2)
      end
      """

      assert fix(code) == code
    end

    test "preserves different variable names in guards" do
      code = """
      defmodule Good do
        defp check(a, b) when a == b, do: :equal
        defp check(c, d) when c != d, do: :not_equal
      end
      """

      assert fix(code) == code
    end

    test "preserves compound guards" do
      code = """
      defmodule Good do
        def foo(a, b) when a == b, do: :equal
        def foo(a, b) when a != b and a > 0, do: :positive_unequal
      end
      """

      assert fix(code) == code
    end

    test "preserves pattern matching (correct approach)" do
      code = """
      defmodule Good do
        defp compare([val | t1], [val | t2]), do: compare(t1, t2)
        defp compare([missing | _], _), do: missing
      end
      """

      assert fix(code) == code
    end

    test "preserves single-clause functions" do
      code = """
      defmodule Good do
        def not_equal?(a, b) when a != b, do: true
      end
      """

      assert fix(code) == code
    end

    test "preserves different function names" do
      code = """
      defmodule Good do
        def equal(a, b) when a == b, do: true
        def not_equal(a, b) when a != b, do: true
      end
      """

      assert fix(code) == code
    end

    # ── Fix: does NOT remove guard when variable names differ ───

    test "does not remove guard when variable names differ across clauses" do
      code = """
      defmodule Good do
        defp check(a, b) when a == b, do: :equal
        defp check(c, d) when c != d, do: :not_equal
      end
      """

      fixed = fix(code)
      assert fixed =~ "when c != d"
    end
  end
end
