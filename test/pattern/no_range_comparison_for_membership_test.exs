defmodule Credence.Pattern.NoRangeComparisonForMembershipTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRangeComparisonForMembership

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRangeComparisonForMembership.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoRangeComparisonForMembership, code, [])

  describe "check" do
    test "detects x >= a and x <= b" do
      code = """
      defmodule M do
        def valid?(x) do
          x >= 10 and x <= 25
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_range_comparison_for_membership
    end

    test "detects x >= a and b >= x" do
      code = """
      defmodule M do
        def valid?(x) do
          x >= 10 and 25 >= x
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects a <= x and x <= b" do
      code = """
      defmodule M do
        def valid?(x) do
          10 <= x and x <= 25
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects a <= x and b >= x" do
      code = """
      defmodule M do
        def valid?(x) do
          10 <= x and 25 >= x
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT fire on different variables" do
      code = """
      defmodule M do
        def valid?(x, y) do
          x >= 10 and y <= 25
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT fire on non-integer bounds" do
      code = """
      defmodule M do
        def valid?(x, lo, hi) do
          x >= lo and x <= hi
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT fire when low > high" do
      code = """
      defmodule M do
        def valid?(x) do
          x >= 25 and x <= 10
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT fire on OR (only AND)" do
      code = """
      defmodule M do
        def valid?(x) do
          x >= 10 or x <= 25
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT fire on strict inequality" do
      code = """
      defmodule M do
        def valid?(x) do
          x > 10 and x < 25
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "rewrites x >= 10 and x <= 25 to x in 10..25" do
      code = """
      defmodule M do
        def valid?(x) do
          x >= 10 and x <= 25
        end
      end
      """

      result = fix(code)
      assert result =~ "x in 10..25"
      refute result =~ ">="
      refute result =~ "<="
    end

    test "handles reversed operands" do
      code = """
      10 <= x and 25 >= x
      """

      result = fix(code)
      assert result =~ "x in 10..25"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def check(n) do
          valid = n >= 0 and n <= 9
          if valid, do: :ok, else: :error
        end
      end
      """

      result = fix(code)
      assert result =~ "n in 0..9"
      assert result =~ ":ok"
      assert result =~ ":error"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      x >= 10 and x <= 25
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoRangeComparisonForMembership.check(ast, []) == []
    end

    test "preserves character literals in rewrite" do
      code = """
      defmodule M do
        def lowercase?(char) do
          char >= ?a and char <= ?z
        end
      end
      """

      result = fix(code)
      assert result =~ "?a..?z"
      refute result =~ "97..122"
    end
  end
end
