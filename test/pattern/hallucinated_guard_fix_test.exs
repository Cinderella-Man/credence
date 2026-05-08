defmodule Credence.Pattern.HallucinatedGuardFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.HallucinatedGuard.fix(code, [])
  end

  describe "is_pos_integer → is_integer and > 0" do
    test "bare call" do
      assert fix("is_pos_integer(x)") == "is_integer(x) and x > 0"
    end

    test "in a guard" do
      assert fix("def foo(x) when is_pos_integer(x), do: x") ==
               "def foo(x) when is_integer(x) and x > 0, do: x"
    end
  end

  describe "is_non_neg_integer → is_integer and >= 0" do
    test "bare call" do
      assert fix("is_non_neg_integer(x)") == "is_integer(x) and x >= 0"
    end

    test "in a guard" do
      assert fix("def foo(x) when is_non_neg_integer(x), do: x") ==
               "def foo(x) when is_integer(x) and x >= 0, do: x"
    end
  end

  describe "is_neg_integer → is_integer and < 0" do
    test "bare call" do
      assert fix("is_neg_integer(x)") == "is_integer(x) and x < 0"
    end

    test "in a guard" do
      assert fix("def foo(x) when is_neg_integer(x), do: x") ==
               "def foo(x) when is_integer(x) and x < 0, do: x"
    end
  end

  describe "is_non_pos_integer → is_integer and <= 0" do
    test "bare call" do
      assert fix("is_non_pos_integer(x)") == "is_integer(x) and x <= 0"
    end

    test "in a guard" do
      assert fix("def foo(x) when is_non_pos_integer(x), do: x") ==
               "def foo(x) when is_integer(x) and x <= 0, do: x"
    end
  end

  describe "no-ops" do
    test "valid guards unchanged" do
      code = "def foo(x) when is_integer(x) and x > 0, do: x"
      assert fix(code) == code
    end

    test "regular function calls unchanged" do
      code = "Enum.map(list, &is_integer/1)"
      assert fix(code) == code
    end
  end
end
