defmodule Credence.Pattern.NoManualMinCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualMin

  describe "NoManualMin check" do
    test "does not flag strict if a < b, do: a, else: b (value-kind unsafe on ties)" do
      code = """
      defmodule Good do
        def smaller(a, b) do
          if a < b, do: a, else: b
        end
      end
      """

      assert check(NoManualMin, code) == []
    end

    test "detects if a <= b, do: a, else: b" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if a <= b, do: a, else: b
        end
      end
      """

      [issue] = check(NoManualMin, code)
      assert issue.message =~ "min/2"
    end

    test "does not flag strict if b > a, do: a, else: b (value-kind unsafe on ties)" do
      code = """
      defmodule Good do
        def smaller(a, b) do
          if b > a, do: a, else: b
        end
      end
      """

      assert check(NoManualMin, code) == []
    end

    test "detects if b >= a, do: a, else: b (flipped with >=)" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if b >= a, do: a, else: b
        end
      end
      """

      [issue] = check(NoManualMin, code)
      assert issue.message =~ "min/2"
    end

    test "detects if a >= b, do: b, else: a" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if a >= b, do: b, else: a
        end
      end
      """

      [issue] = check(NoManualMin, code)
      assert issue.message =~ "min/2"
    end

    test "detects complex expressions (not just variables)" do
      code = """
      defmodule Bad do
        def clamp_low(value, floor) do
          if value - 1 <= floor, do: value - 1, else: floor
        end
      end
      """

      [issue] = check(NoManualMin, code)
      assert issue.message =~ "min/2"
    end

    test "detects with do/end block syntax" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if a <= b do
            a
          else
            b
          end
        end
      end
      """

      [issue] = check(NoManualMin, code)
      assert issue.message =~ "min/2"
    end

    test "detects multiple instances in one module" do
      code = """
      defmodule Bad do
        def f(a, b, c) do
          x = if a <= b, do: a, else: b
          y = if c >= x, do: x, else: c
          y
        end
      end
      """

      issues = check(NoManualMin, code)
      assert length(issues) == 2
    end

    test "does not flag min/2 usage (already correct)" do
      code = """
      defmodule Good do
        def smaller(a, b), do: min(a, b)
      end
      """

      assert check(NoManualMin, code) == []
    end

    test "does not flag max pattern (different rule)" do
      code = """
      defmodule Good do
        def bigger(a, b) do
          if a > b, do: a, else: b
        end
      end
      """

      assert check(NoManualMin, code) == []
    end

    test "does not flag if with non-comparison condition" do
      code = """
      defmodule Good do
        def pick(flag, a, b) do
          if flag, do: a, else: b
        end
      end
      """

      assert check(NoManualMin, code) == []
    end

    test "does not flag if with mismatched branches" do
      code = """
      defmodule Good do
        def transform(a, b) do
          if a < b, do: a * 2, else: b
        end
      end
      """

      assert check(NoManualMin, code) == []
    end

    test "does not flag if without else" do
      code = """
      defmodule Good do
        def maybe(a, b) do
          if a < b, do: a
        end
      end
      """

      assert check(NoManualMin, code) == []
    end

    test "does not flag if where branches are swapped (would be max)" do
      code = """
      defmodule Good do
        def bigger(a, b) do
          if a < b, do: b, else: a
        end
      end
      """

      assert check(NoManualMin, code) == []
    end
  end
end
