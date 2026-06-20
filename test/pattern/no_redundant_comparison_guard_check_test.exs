defmodule Credence.Pattern.NoRedundantComparisonGuardCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantComparisonGuard

  describe "check — positive cases (should flag)" do
    test "flags n >= 0 when earlier clause has n < 0 with same type guard" do
      code = """
      defmodule Bad do
        def sqrt(n) when is_number(n) and n < 0, do: raise(ArgumentError)
        def sqrt(0), do: 0.0
        def sqrt(n) when is_number(n) and n >= 0, do: :ok
      end
      """

      [issue] = check(NoRedundantComparisonGuard, code)
      assert issue.rule == :no_redundant_comparison_guard
      assert issue.message =~ ">= 0"
      assert issue.message =~ "Redundant"
    end

    test "flags n <= 0 when earlier clause has n > 0 with same type guard" do
      code = """
      defmodule Bad do
        def f(n) when is_number(n) and n > 0, do: :positive
        def f(n) when is_number(n) and n <= 0, do: :non_positive
      end
      """

      [issue] = check(NoRedundantComparisonGuard, code)
      assert issue.message =~ "<= 0"
    end

    test "flags n > 5 when earlier clause has n <= 5 with is_integer" do
      code = """
      defmodule Bad do
        def classify(n) when is_integer(n) and n <= 5, do: :small
        def classify(n) when is_integer(n) and n > 5, do: :big
      end
      """

      [issue] = check(NoRedundantComparisonGuard, code)
      assert issue.message =~ "> 5"
    end

    test "flags n < 10 when earlier clause has n >= 10" do
      code = """
      defmodule Bad do
        def bucket(n) when is_number(n) and n >= 10, do: :high
        def bucket(n) when is_number(n) and n < 10, do: :low
      end
      """

      [issue] = check(NoRedundantComparisonGuard, code)
      assert issue.message =~ "< 10"
    end

    test "flags with intermediate clauses (the Newton-Raphson pattern)" do
      code = """
      defmodule Bad do
        def newton_raphson_sqrt(n) when is_number(n) and n < 0 do
          raise ArgumentError, "negative"
        end

        def newton_raphson_sqrt(0), do: 0.0

        def newton_raphson_sqrt(n) when is_number(n) and n >= 0 do
          :ok
        end
      end
      """

      [issue] = check(NoRedundantComparisonGuard, code)
      assert issue.rule == :no_redundant_comparison_guard
      assert issue.message =~ ">= 0"
    end

    test "flags in defp (not just def)" do
      code = """
      defmodule Bad do
        defp step(n) when is_integer(n) and n < 0, do: :back
        defp step(n) when is_integer(n) and n >= 0, do: :forward
      end
      """

      [issue] = check(NoRedundantComparisonGuard, code)
      assert issue.message =~ ">= 0"
    end

    test "flags comparison with reversed operand order in guard" do
      code = """
      defmodule Bad do
        def f(n) when is_number(n) and n < 0, do: :a
        def f(n) when is_number(n) and 0 <= n, do: :b
      end
      """

      # 0 <= n is n >= 0, which is complementary to n < 0
      [issue] = check(NoRedundantComparisonGuard, code)
      assert issue.rule == :no_redundant_comparison_guard
    end

    test "flags atom-typed complementary guards (term order is total)" do
      code = """
      defmodule Bad do
        def f(n) when is_atom(n) and n < 0, do: :a
        def f(n) when is_atom(n) and n >= 0, do: :b
      end
      """

      [issue] = check(NoRedundantComparisonGuard, code)
      assert issue.rule == :no_redundant_comparison_guard
    end
  end

  describe "check — negative cases (should NOT flag)" do
    test "does not flag bare comparisons without type guards" do
      code = """
      defmodule Good do
        def f(n) when n < 0, do: :negative
        def f(n) when n >= 0, do: :non_negative
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    test "does not flag different type guards" do
      code = """
      defmodule Good do
        def f(n) when is_integer(n) and n < 0, do: :negative_int
        def f(n) when is_number(n) and n >= 0, do: :non_negative_num
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    test "does not flag different variables" do
      code = """
      defmodule Good do
        def f(a, b) when is_number(a) and a < 0, do: :a
        def f(a, b) when is_number(b) and b >= 0, do: :b
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    test "does not flag different literals" do
      code = """
      defmodule Good do
        def f(n) when is_number(n) and n < 0, do: :a
        def f(n) when is_number(n) and n >= 5, do: :b
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    test "does not flag non-complementary operators" do
      code = """
      defmodule Good do
        def f(n) when is_number(n) and n < 0, do: :a
        def f(n) when is_number(n) and n < 5, do: :b
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    test "does not flag single-clause functions" do
      code = """
      defmodule Good do
        def f(n) when is_number(n) and n >= 0, do: :ok
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    test "does not flag unrelated guards" do
      code = """
      defmodule Good do
        def f(n) when is_number(n) and n < 0, do: :negative
        def f(n) when is_number(n) and n > 10, do: :big
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    test "does not flag when guard has additional constraints" do
      code = """
      defmodule Good do
        def f(n) when is_atom(n) and n < 0, do: :negative_atom
        def f(n) when is_number(n) and n >= 0, do: :non_negative
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    test "does not flag clauses without guards" do
      code = """
      defmodule Good do
        def f(n) when is_number(n) and n < 0, do: :negative
        def f(n), do: :other
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    # The earlier complementary clause has a DIFFERENT head pattern (the second
    # argument's type tag differs), so it never consumed the domain reaching the
    # later clause — the comparison there is NOT redundant. Dropping it would let
    # negatives match the non_neg_integer clause and return :ok.
    test "does not flag when the complementary earlier clause has a different head pattern" do
      code = """
      defmodule Good do
        def match_type(value, {:type, 0, :neg_integer, []}) when is_integer(value) and value < 0,
          do: :ok

        def match_type(value, {:type, 0, :non_neg_integer, []})
            when is_integer(value) and value >= 0,
            do: :ok

        def match_type(_value, _type), do: :mismatch
      end
      """

      assert check(NoRedundantComparisonGuard, code) == []
    end

    # Same head pattern in both clauses → the earlier clause genuinely consumed
    # the complementary domain, so the later comparison IS redundant.
    test "still flags when the complementary earlier clause has the same head pattern" do
      code = """
      defmodule Bad do
        def f({:tuple, n}, acc) when is_integer(n) and n >= 0, do: {:pos, n, acc}
        def f({:tuple, n}, acc) when is_integer(n) and n < 0, do: {:neg, n, acc}
        def f({:tuple, n}, acc), do: {:other, n, acc}
      end
      """

      assert [%{rule: :no_redundant_comparison_guard}] = check(NoRedundantComparisonGuard, code)
    end
  end
end
