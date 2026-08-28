defmodule Credence.Pattern.NoRedundantNegatedGuardFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantNegatedGuard

  describe "fix" do
    test "removes != guard when preceded by == guard" do
      input = """
      defmodule Bad do
        defp compare([v1 | t1], [v2 | t2]) when v1 == v2, do: compare(t1, t2)
        defp compare([v1 | _], [v2 |_ ]) when v1 != v2, do: v1
      end
      """

      expected = """
      defmodule Bad do
        defp compare([v1 | t1], [v2 | t2]) when v1 == v2, do: compare(t1, t2)
        defp compare([v1 | _], [v2 | _]), do: v1
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, input), expected)
    end

    test "removes !== guard when preceded by === guard" do
      input = """
      defmodule Bad do
        defp match(a, b) when a === b, do: :equal
        defp match(a, b) when a !== b, do: :not_equal
      end
      """

      expected = """
      defmodule Bad do
        defp match(a, b) when a === b, do: :equal
        defp match(a, b), do: :not_equal
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, input), expected)
    end

    test "removes != guard in def (not just defp)" do
      input = """
      defmodule Bad do
        def compare(x, y) when x == y, do: :same
        def compare(x, y) when x != y, do: :different
      end
      """

      expected = """
      defmodule Bad do
        def compare(x, y) when x == y, do: :same
        def compare(x, y), do: :different
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, input), expected)
    end

    test "removes guard in longer function with multiple clauses" do
      input = """
      defmodule Bad do
        defp process([h | _], []), do: h
        defp process([a | t1], [b | t2]) when a == b, do: process(t1, t2)
        defp process([a | _], [b |_ ]) when a != b, do: a
      end
      """

      expected = """
      defmodule Bad do
        defp process([h | _], []), do: h
        defp process([a | t1], [b | t2]) when a == b, do: process(t1, t2)
        defp process([a | _], [b | _]), do: a
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, input), expected)
    end

    test "handles multi-line guard clause" do
      input = """
      defmodule Bad do
        defp compare([v1 | t1], [v2 | t2])
            when v1 == v2,
            do: compare(t1, t2)

        defp compare([v1 | _], [v2 |_ ])
            when v1 != v2,
            do: v1
      end
      """

      expected = """
      defmodule Bad do
        defp compare([v1 | t1], [v2 | t2])
            when v1 == v2,
            do: compare(t1, t2)

        defp compare([v1 | _], [v2 | _]),
            do: v1
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, input), expected)
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

      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "preserves clause without guard following equality guard" do
      code = """
      defmodule Good do
        defp walk([a | t1], [b | t2]) when a == b, do: walk(t1, t2)
        defp walk([missing | _], _), do: missing
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "preserves negated guard without preceding equality" do
      code = """
      defmodule Good do
        defp compare([a | _], [b | _]) when a != b, do: a
        defp compare([_ | t1], [_ | t2]), do: compare(t1, t2)
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "preserves different variable names in guards" do
      code = """
      defmodule Good do
        defp check(a, b) when a == b, do: :equal
        defp check(c, d) when c != d, do: :not_equal
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "preserves compound guards" do
      code = """
      defmodule Good do
        def foo(a, b) when a == b, do: :equal
        def foo(a, b) when a != b and a > 0, do: :positive_unequal
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "preserves pattern matching (correct approach)" do
      code = """
      defmodule Good do
        defp compare([val | t1], [val | t2]), do: compare(t1, t2)
        defp compare([missing | _], _), do: missing
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "preserves single-clause functions" do
      code = """
      defmodule Good do
        def not_equal?(a, b) when a != b, do: true
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "preserves different function names" do
      code = """
      defmodule Good do
        def equal(a, b) when a == b, do: true
        def not_equal(a, b) when a != b, do: true
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "does not remove guard when variable names differ across clauses" do
      code = """
      defmodule Good do
        defp check(a, b) when a == b, do: :equal
        defp check(c, d) when c != d, do: :not_equal
      end
      """

      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "preserves mixed loose and strict comparison operators" do
      code = """
      defmodule MixedComparisonOperators do
        def compare(x, y) when x === y, do: :same
        def compare(x, y) when x != y, do: :different
      end
      """

      assert clean?(NoRedundantNegatedGuard, code)
      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "preserves guards when the clause argument patterns differ" do
      code = """
      defmodule DifferentArgumentPatterns do
        def compare([x], y) when x == y, do: :same
        def compare(x, y) when x != y, do: :different
      end
      """

      assert clean?(NoRedundantNegatedGuard, code)
      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end

    test "does not pair clauses from separate modules" do
      code = """
      defmodule EqualityModule do
        def compare(x, y) when x == y, do: :same
      end

      defmodule InequalityModule do
        def compare(x, y) when x != y, do: :different
      end
      """

      assert clean?(NoRedundantNegatedGuard, code)
      confirm_fix(fix(NoRedundantNegatedGuard, code), code)
    end
  end
end
