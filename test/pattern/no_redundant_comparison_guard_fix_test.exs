defmodule Credence.Pattern.NoRedundantComparisonGuardFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantComparisonGuard

  describe "fix — removes the redundant comparison conjunct, keeps the type guard" do
    test "n >= 0 after n < 0 (with intermediate pattern clause)" do
      code = """
      defmodule Bad do
        def sqrt(n) when is_number(n) and n < 0, do: raise(ArgumentError)
        def sqrt(0), do: 0.0
        def sqrt(n) when is_number(n) and n >= 0, do: :ok
      end
      """

      expected = """
      defmodule Bad do
        def sqrt(n) when is_number(n) and n < 0, do: raise(ArgumentError)
        def sqrt(0), do: 0.0
        def sqrt(n) when is_number(n), do: :ok
      end
      """

      confirm_fix(fix(NoRedundantComparisonGuard, code), expected)
    end

    test "n <= 0 after n > 0" do
      code = """
      defmodule Bad do
        def f(n) when is_number(n) and n > 0, do: :positive
        def f(n) when is_number(n) and n <= 0, do: :non_positive
      end
      """

      expected = """
      defmodule Bad do
        def f(n) when is_number(n) and n > 0, do: :positive
        def f(n) when is_number(n), do: :non_positive
      end
      """

      confirm_fix(fix(NoRedundantComparisonGuard, code), expected)
    end

    test "n > 5 after n <= 5 with is_integer" do
      code = """
      defmodule Bad do
        def classify(n) when is_integer(n) and n <= 5, do: :small
        def classify(n) when is_integer(n) and n > 5, do: :big
      end
      """

      expected = """
      defmodule Bad do
        def classify(n) when is_integer(n) and n <= 5, do: :small
        def classify(n) when is_integer(n), do: :big
      end
      """

      confirm_fix(fix(NoRedundantComparisonGuard, code), expected)
    end

    test "reversed operand order (0 <= n)" do
      code = """
      defmodule Bad do
        def f(n) when is_number(n) and n < 0, do: :a
        def f(n) when is_number(n) and 0 <= n, do: :b
      end
      """

      expected = """
      defmodule Bad do
        def f(n) when is_number(n) and n < 0, do: :a
        def f(n) when is_number(n), do: :b
      end
      """

      confirm_fix(fix(NoRedundantComparisonGuard, code), expected)
    end

    test "multi-line clause bodies preserve structure" do
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

      expected = """
      defmodule Bad do
        def newton_raphson_sqrt(n) when is_number(n) and n < 0 do
          raise ArgumentError, "negative"
        end

        def newton_raphson_sqrt(0), do: 0.0

        def newton_raphson_sqrt(n) when is_number(n) do
          :ok
        end
      end
      """

      confirm_fix(fix(NoRedundantComparisonGuard, code), expected)
    end

    test "defp clause" do
      code = """
      defmodule Bad do
        defp step(n) when is_integer(n) and n < 0, do: :back
        defp step(n) when is_integer(n) and n >= 0, do: :forward
      end
      """

      expected = """
      defmodule Bad do
        defp step(n) when is_integer(n) and n < 0, do: :back
        defp step(n) when is_integer(n), do: :forward
      end
      """

      confirm_fix(fix(NoRedundantComparisonGuard, code), expected)
    end
  end

  describe "fix — no-op on cases check does not flag" do
    test "different type guards left untouched" do
      code = """
      defmodule Good do
        def f(n) when is_integer(n) and n < 0, do: :negative_int
        def f(n) when is_number(n) and n >= 0, do: :non_negative_num
      end
      """

      confirm_fix(fix(NoRedundantComparisonGuard, code), code)
    end

    test "bare comparisons without type guards left untouched" do
      code = """
      defmodule Good do
        def f(n) when n < 0, do: :negative
        def f(n) when n >= 0, do: :non_negative
      end
      """

      confirm_fix(fix(NoRedundantComparisonGuard, code), code)
    end

    test "non-complementary operators left untouched" do
      code = """
      defmodule Good do
        def f(n) when is_number(n) and n < 0, do: :a
        def f(n) when is_number(n) and n < 5, do: :b
      end
      """

      confirm_fix(fix(NoRedundantComparisonGuard, code), code)
    end
  end
end
