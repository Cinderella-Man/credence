defmodule Credence.Pattern.NoKernelShadowingFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(Credence.Pattern.NoKernelShadowing, code, [])
  end

  describe "max → max_value" do
    test "fn parameter and body" do
      assert fix("Enum.reduce(list, 0, fn x, max -> max(x, max) end)") ==
               "Enum.reduce(list, 0, fn x, max_value -> max(x, max_value) end)"
    end

    test "def parameter" do
      assert fix("defp go([], max), do: max") == "defp go([], max_value), do: max_value"
    end

    test "match assignment" do
      assert fix("max = Enum.max(list)") == "max_value = Enum.max(list)"
    end
  end

  describe "min → min_value" do
    test "fn parameter" do
      assert fix("Enum.reduce(list, 999, fn x, min -> min(x, min) end)") ==
               "Enum.reduce(list, 999, fn x, min_value -> min(x, min_value) end)"
    end
  end

  describe "other renames" do
    test "hd → head" do
      assert fix("Enum.map(list, fn hd -> hd + 1 end)") ==
               "Enum.map(list, fn head -> head + 1 end)"
    end

    test "tl → tail" do
      assert fix("[_ | tl] = list") == "[_ | tail] = list"
    end

    test "elem → element" do
      assert fix("Enum.map(tuples, fn elem -> elem end)") ==
               "Enum.map(tuples, fn element -> element end)"
    end

    test "div → quotient" do
      assert fix("div = div(a, b)") == "quotient = div(a, b)"
    end

    test "rem → remainder" do
      assert fix("rem = rem(a, b)") == "remainder = rem(a, b)"
    end

    test "length → count" do
      assert fix("length = length(list)") == "count = length(list)"
    end
  end

  describe "preserves non-shadowing code" do
    test "Kernel function calls untouched" do
      code = "max(a, b)"
      assert fix(code) == code
    end

    test "idiomatic names untouched" do
      code = "Enum.reduce(list, 0, fn x, max_val -> max(x, max_val) end)"
      assert fix(code) == code
    end

    test "map keys untouched" do
      code = "%{max: 10, min: 0}"
      assert fix(code) == code
    end
  end
end
