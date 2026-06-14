defmodule Credence.Pattern.PreferIntegerUndigitsFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferIntegerUndigits

  describe "rewrites the anti-pattern" do
    test "acc * 10 + elem form" do
      input = "Enum.reduce(digits, 0, fn digit, acc -> acc * 10 + digit end)"

      expected = "Integer.undigits(digits)"

      confirm_fix(fix(PreferIntegerUndigits, input), expected)
    end

    test "elem + acc * 10 form (commutative addition)" do
      input = "Enum.reduce(digits, 0, fn digit, acc -> digit + acc * 10 end)"

      expected = "Integer.undigits(digits)"

      confirm_fix(fix(PreferIntegerUndigits, input), expected)
    end

    test "preserves surrounding code" do
      input = """
      defmodule M do
        def max_number(n) do
          digits = Integer.digits(n)
          sorted_digits = Enum.sort(digits, :desc)
          Enum.reduce(sorted_digits, 0, fn digit, acc -> acc * 10 + digit end)
        end
      end
      """

      expected = """
      defmodule M do
        def max_number(n) do
          digits = Integer.digits(n)
          sorted_digits = Enum.sort(digits, :desc)
          Integer.undigits(sorted_digits)
        end
      end
      """

      confirm_fix(fix(PreferIntegerUndigits, input), expected)
    end

    test "does not modify non-undigits reductions" do
      code = "Enum.reduce(list, 0, fn x, acc -> acc + x end)"

      confirm_fix(fix(PreferIntegerUndigits, code), code)
    end

    test "round-trip: fixed code produces no issues" do
      code = "Enum.reduce(digits, 0, fn digit, acc -> acc * 10 + digit end)"

      fixed = fix(PreferIntegerUndigits, code)
      assert clean?(PreferIntegerUndigits, fixed)
    end
  end
end
