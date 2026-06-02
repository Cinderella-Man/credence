defmodule Credence.Pattern.NoRedundantRemGuardTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRedundantRemGuard

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRedundantRemGuard.check(ast, [])
  end

  describe "NoRedundantRemGuard" do
    # ── Positive cases (should flag) ────────────────────────────

    test "detects rem(x, 2) == 0 followed by rem(x, 2) == 1" do
      code = """
      defmodule Bad do
        defp classify(x) when rem(x, 2) == 0, do: :even
        defp classify(x) when rem(x, 2) == 1, do: :odd
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_redundant_rem_guard
      assert issue.message =~ "rem(x, 2) == 1"
      assert issue.message =~ "Redundant"
    end

    test "detects rem(x, 2) == 1 followed by rem(x, 2) == 0" do
      code = """
      defmodule Bad do
        defp classify(x) when rem(x, 2) == 1, do: :odd
        defp classify(x) when rem(x, 2) == 0, do: :even
      end
      """

      [issue] = check(code)
      assert issue.message =~ "rem(x, 2) == 0"
    end

    test "detects rem(x, 2) == 0 followed by rem(x, 2) != 0" do
      code = """
      defmodule Bad do
        defp classify(x) when rem(x, 2) == 0, do: :even
        defp classify(x) when rem(x, 2) != 0, do: :odd
      end
      """

      [issue] = check(code)
      assert issue.message =~ "rem(x, 2) != 0"
    end

    test "detects in compound guard" do
      code = """
      defmodule Bad do
        defp power(_base, 0), do: 1
        defp power(base, exp) when rem(exp, 2) == 0, do: power(base * base, div(exp, 2))
        defp power(base, exp) when is_integer(exp) and rem(exp, 2) == 1, do: base * power(base, exp - 1)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "rem(exp, 2) == 1"
    end

    test "detects in def (not just defp)" do
      code = """
      defmodule Bad do
        def classify(x) when rem(x, 2) == 0, do: :even
        def classify(x) when rem(x, 2) == 1, do: :odd
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_redundant_rem_guard
    end

    test "detects rem(x, 2) != 0 in preceding guard followed by rem(x, 2) == 0" do
      code = """
      defmodule Bad do
        defp classify(x) when rem(x, 2) != 0, do: :odd
        defp classify(x) when rem(x, 2) == 0, do: :even
      end
      """

      [issue] = check(code)
      assert issue.message =~ "rem(x, 2) == 0"
    end

    test "detects rem(x, 2) != 1 in preceding guard followed by rem(x, 2) == 1" do
      code = """
      defmodule Bad do
        defp classify(x) when rem(x, 2) != 1, do: :even
        defp classify(x) when rem(x, 2) == 1, do: :odd
      end
      """

      [issue] = check(code)
      assert issue.message =~ "rem(x, 2) == 1"
    end

    # ── Negative cases (should NOT flag) ────────────────────────

    test "does not flag rem(x, 3) followed by rem(x, 3) with different values" do
      code = """
      defmodule Good do
        defp classify(x) when rem(x, 3) == 0, do: :zero
        defp classify(x) when rem(x, 3) == 1, do: :one
      end
      """

      assert check(code) == []
    end

    test "does not flag without preceding rem guard" do
      code = """
      defmodule Good do
        defp classify(x) when x > 0, do: :positive
        defp classify(x) when rem(x, 2) == 1, do: :odd_positive
      end
      """

      assert check(code) == []
    end

    test "does not flag single-clause functions" do
      code = """
      defmodule Good do
        def classify(x) when rem(x, 2) == 1, do: :odd
      end
      """

      assert check(code) == []
    end

    test "does not flag different variable names across clauses" do
      code = """
      defmodule Good do
        defp classify(x) when rem(x, 2) == 0, do: :even
        defp classify(y) when rem(y, 2) == 1, do: :odd
      end
      """

      assert check(code) == []
    end

    test "does not flag non-adjacent rem clauses" do
      code = """
      defmodule Good do
        defp classify(x) when rem(x, 2) == 0, do: :even
        defp classify(x) when x > 10, do: :big
        defp classify(x) when rem(x, 2) == 1, do: :odd
      end
      """

      assert check(code) == []
    end

    test "does not flag rem(x, 2) != 0 followed by rem(x, 2) == 1 (same parity)" do
      code = """
      defmodule Good do
        defp classify(x) when rem(x, 2) != 0, do: :odd
        defp classify(x) when rem(x, 2) == 1, do: :odd_positive
      end
      """

      assert check(code) == []
    end

    test "does not flag rem(x, 2) != 1 followed by rem(x, 2) == 0 (same parity)" do
      code = """
      defmodule Good do
        defp classify(x) when rem(x, 2) != 1, do: :even
        defp classify(x) when rem(x, 2) == 0, do: :even_nonneg
      end
      """

      assert check(code) == []
    end

    test "flags recur_power pattern from row 54555" do
      code = """
      defmodule Solution do
        def recur_power(_base, 0), do: 1

        def recur_power(base, exp) when is_integer(base) and is_integer(exp) and exp < 0,
          do: 1.0 / recur_power(base, -exp)

        def recur_power(base, exp) when is_integer(base) and is_integer(exp) and rem(exp, 2) == 0,
          do: recur_power(base * base, div(exp, 2))

        def recur_power(base, exp) when is_integer(base) and is_integer(exp) and rem(exp, 2) == 1,
          do: base * recur_power(base, exp - 1)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_redundant_rem_guard
      assert issue.message =~ "rem(exp, 2) == 1"
    end
  end
end
