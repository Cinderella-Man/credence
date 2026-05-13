defmodule Credence.Semantic.UndefinedLocalFunctionFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedLocalFunction

  defp fix(source, message, line \\ 1) do
    UndefinedLocalFunction.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  @infinity_msg "undefined function infinity/0 (expected MyModule to define such a function or for it to be imported, but none are available)"

  @max_msg "undefined function max/1 (expected MaxProductThree to define such a function or for it to be imported, but none are available)"

  # ── infinity() → :math.inf() ──────────────────────────────────

  describe "infinity() → :math.inf()" do
    test "standalone call" do
      assert fix("infinity()", @infinity_msg) == ":math.inf()"
    end

    test "negated" do
      assert fix("-infinity()", @infinity_msg) == "-:math.inf()"
    end

    test "in a tuple" do
      assert fix("{-infinity(), -infinity()}", @infinity_msg) ==
               "{-:math.inf(), -:math.inf()}"
    end

    test "in Enum.reduce accumulator" do
      input = "Enum.reduce(nums, {-infinity(), -infinity()}, fn x, acc -> x end)"

      assert fix(input, @infinity_msg) ==
               "Enum.reduce(nums, {-:math.inf(), -:math.inf()}, fn x, acc -> x end)"
    end

    test "only on reported line" do
      input = "x = infinity()\ny = infinity()"

      assert fix(input, @infinity_msg, 2) ==
               "x = infinity()\ny = :math.inf()"
    end
  end

  # ── max(list) → Enum.max(list) ────────────────────────────────

  describe "max(list) → Enum.max(list)" do
    test "with list literal" do
      assert fix("max([option1, option2])", @max_msg) ==
               "Enum.max([option1, option2])"
    end

    test "with variable" do
      assert fix("max(values)", @max_msg) ==
               "Enum.max(values)"
    end

    test "in assignment" do
      assert fix("result = max([a, b, c])", @max_msg) ==
               "result = Enum.max([a, b, c])"
    end

    test "realistic context from LLM log" do
      code =
        "    option1 = List.last(sorted) * Enum.at(sorted, -2) * Enum.at(sorted, -3)\n" <>
          "    option2 = List.first(sorted) * Enum.at(sorted, -1) * List.last(sorted)\n" <>
          "\n" <>
          "    max([option1, option2])"

      expected =
        "    option1 = List.last(sorted) * Enum.at(sorted, -2) * Enum.at(sorted, -3)\n" <>
          "    option2 = List.first(sorted) * Enum.at(sorted, -1) * List.last(sorted)\n" <>
          "\n" <>
          "    Enum.max([option1, option2])"

      assert fix(code, @max_msg, 4) == expected
    end

    test "only on reported line" do
      input = "x = max(a, b)\ny = max([option1, option2])"

      assert fix(input, @max_msg, 2) ==
               "x = max(a, b)\ny = Enum.max([option1, option2])"
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "unknown local function unchanged" do
      source = "foobar()"
      msg = "undefined function foobar/0 (expected MyModule to define such a function)"
      assert fix(source, msg) == source
    end
  end
end
