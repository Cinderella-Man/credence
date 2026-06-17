defmodule Credence.Pattern.HallucinatedGuardFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.HallucinatedGuard

  describe "is_pos_integer → is_integer and > 0" do
    test "bare call" do
      confirm_fix(fix(HallucinatedGuard, "is_pos_integer(x)"), "is_integer(x) and x > 0")
    end

    test "in a guard" do
      confirm_fix(
        fix(HallucinatedGuard, "def foo(x) when is_pos_integer(x), do: x"),
        "def foo(x) when is_integer(x) and x > 0, do: x"
      )
    end
  end

  describe "is_non_neg_integer → is_integer and >= 0" do
    test "bare call" do
      confirm_fix(fix(HallucinatedGuard, "is_non_neg_integer(x)"), "is_integer(x) and x >= 0")
    end

    test "in a guard" do
      confirm_fix(
        fix(HallucinatedGuard, "def foo(x) when is_non_neg_integer(x), do: x"),
        "def foo(x) when is_integer(x) and x >= 0, do: x"
      )
    end
  end

  describe "is_neg_integer → is_integer and < 0" do
    test "bare call" do
      confirm_fix(fix(HallucinatedGuard, "is_neg_integer(x)"), "is_integer(x) and x < 0")
    end

    test "in a guard" do
      confirm_fix(
        fix(HallucinatedGuard, "def foo(x) when is_neg_integer(x), do: x"),
        "def foo(x) when is_integer(x) and x < 0, do: x"
      )
    end
  end

  describe "is_non_pos_integer → is_integer and <= 0" do
    test "bare call" do
      confirm_fix(fix(HallucinatedGuard, "is_non_pos_integer(x)"), "is_integer(x) and x <= 0")
    end

    test "in a guard" do
      confirm_fix(
        fix(HallucinatedGuard, "def foo(x) when is_non_pos_integer(x), do: x"),
        "def foo(x) when is_integer(x) and x <= 0, do: x"
      )
    end
  end

  describe "no-ops" do
    test "valid guards unchanged" do
      code = "def foo(x) when is_integer(x) and x > 0, do: x"

      confirm_fix(fix(HallucinatedGuard, code), code)
    end

    test "regular function calls unchanged" do
      code = "Enum.map(list, &is_integer/1)"

      confirm_fix(fix(HallucinatedGuard, code), code)
    end
  end
end
