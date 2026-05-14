defmodule Credence.Semantic.UndefinedFunction.LocalFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  defp msg(name, arity) do
    "undefined function #{name}/#{arity} (expected MyModule to define such a function or for it to be imported, but none are available)"
  end

  # ── infinity ───────────────────────────────────────────────────

  describe "infinity() → :math.inf()" do
    test "standalone call" do
      assert fix("infinity()", msg("infinity", 0)) == ":math.inf()"
    end

    test "negated" do
      assert fix("-infinity()", msg("infinity", 0)) == "-:math.inf()"
    end

    test "in a tuple" do
      assert fix("{-infinity(), -infinity()}", msg("infinity", 0)) ==
               "{-:math.inf(), -:math.inf()}"
    end

    test "in Enum.reduce accumulator" do
      input = "Enum.reduce(nums, {-infinity(), -infinity()}, fn x, acc -> x end)"

      assert fix(input, msg("infinity", 0)) ==
               "Enum.reduce(nums, {-:math.inf(), -:math.inf()}, fn x, acc -> x end)"
    end

    test "only on reported line" do
      input = "x = infinity()\ny = infinity()"

      assert fix(input, msg("infinity", 0), 2) == "x = infinity()\ny = :math.inf()"
    end
  end

  # ── max/1 rename ───────────────────────────────────────────────

  describe "max/1 → Enum.max(list)" do
    test "with list literal" do
      assert fix("max([option1, option2])", msg("max", 1)) == "Enum.max([option1, option2])"
    end

    test "with variable" do
      assert fix("max(values)", msg("max", 1)) == "Enum.max(values)"
    end

    test "in assignment" do
      assert fix("result = max([a, b, c])", msg("max", 1)) == "result = Enum.max([a, b, c])"
    end

    test "realistic context from LLM log" do
      code =
        "    option1 = List.last(sorted) * Enum.at(sorted, -2) * Enum.at(sorted, -3)\n" <>
          "    option2 = List.first(sorted) * Enum.at(sorted, -1) * List.last(sorted)\n" <>
          "\n" <> "    max([option1, option2])"

      expected =
        "    option1 = List.last(sorted) * Enum.at(sorted, -2) * Enum.at(sorted, -3)\n" <>
          "    option2 = List.first(sorted) * Enum.at(sorted, -1) * List.last(sorted)\n" <>
          "\n" <> "    Enum.max([option1, option2])"

      assert fix(code, msg("max", 1), 4) == expected
    end

    test "only on reported line" do
      input = "x = max(a, b)\ny = max([option1, option2])"

      assert fix(input, msg("max", 1), 2) == "x = max(a, b)\ny = Enum.max([option1, option2])"
    end
  end

  # ── max/3,4,5 wrap-args ────────────────────────────────────────

  describe "max/3 → Enum.max([a, b, c])" do
    test "three simple args" do
      assert fix("max(a, b, c)", msg("max", 3)) == "Enum.max([a, b, c])"
    end

    test "in assignment" do
      assert fix("result = max(x, y, z)", msg("max", 3)) == "result = Enum.max([x, y, z])"
    end

    test "with nested function call" do
      assert fix("max(foo(x), bar(y), z)", msg("max", 3)) == "Enum.max([foo(x), bar(y), z])"
    end

    test "preserves inner Kernel.max/2" do
      assert fix("max(a, max(b, c), d)", msg("max", 3)) == "Enum.max([a, max(b, c), d])"
    end
  end

  describe "max/4 → Enum.max([a, b, c, d])" do
    test "four simple args" do
      assert fix("max(a, b, c, d)", msg("max", 4)) == "Enum.max([a, b, c, d])"
    end
  end

  describe "max/5 → Enum.max([a, b, c, d, e])" do
    test "five simple args" do
      assert fix("max(a, b, c, d, e)", msg("max", 5)) == "Enum.max([a, b, c, d, e])"
    end
  end

  # ── min/1 rename ───────────────────────────────────────────────

  describe "min/1 → Enum.min(list)" do
    test "with list literal" do
      assert fix("min([a, b])", msg("min", 1)) == "Enum.min([a, b])"
    end

    test "with variable" do
      assert fix("min(values)", msg("min", 1)) == "Enum.min(values)"
    end

    test "in assignment" do
      assert fix("lowest = min([x, y, z])", msg("min", 1)) == "lowest = Enum.min([x, y, z])"
    end
  end

  # ── min/3,4,5 wrap-args ────────────────────────────────────────

  describe "min/3 → Enum.min([a, b, c])" do
    test "three simple args" do
      assert fix("min(a, b, c)", msg("min", 3)) == "Enum.min([a, b, c])"
    end

    test "with nested function call" do
      assert fix("min(foo(x), bar(y), z)", msg("min", 3)) == "Enum.min([foo(x), bar(y), z])"
    end

    test "preserves inner Kernel.min/2" do
      assert fix("min(a, min(b, c), d)", msg("min", 3)) == "Enum.min([a, min(b, c), d])"
    end
  end

  describe "min/4 → Enum.min([a, b, c, d])" do
    test "four simple args" do
      assert fix("min(a, b, c, d)", msg("min", 4)) == "Enum.min([a, b, c, d])"
    end
  end

  describe "min/5 → Enum.min([a, b, c, d, e])" do
    test "five simple args" do
      assert fix("min(a, b, c, d, e)", msg("min", 5)) == "Enum.min([a, b, c, d, e])"
    end
  end

  # ── Python built-ins ───────────────────────────────────────────

  describe "sum/1 → Enum.sum" do
    test "with variable" do
      assert fix("sum(numbers)", msg("sum", 1)) == "Enum.sum(numbers)"
    end

    test "with list literal" do
      assert fix("sum([1, 2, 3])", msg("sum", 1)) == "Enum.sum([1, 2, 3])"
    end

    test "in assignment" do
      assert fix("total = sum(values)", msg("sum", 1)) == "total = Enum.sum(values)"
    end
  end

  describe "sorted/1 → Enum.sort" do
    test "with variable" do
      assert fix("sorted(numbers)", msg("sorted", 1)) == "Enum.sort(numbers)"
    end

    test "in pipeline" do
      assert fix("result = sorted(items) |> Enum.take(5)", msg("sorted", 1)) ==
               "result = Enum.sort(items) |> Enum.take(5)"
    end
  end

  describe "len/1 → length" do
    test "with variable" do
      assert fix("len(items)", msg("len", 1)) == "length(items)"
    end

    test "in comparison" do
      assert fix("if len(list) > 0, do: :ok", msg("len", 1)) ==
               "if length(list) > 0, do: :ok"
    end

    test "in assignment" do
      assert fix("n = len(words)", msg("len", 1)) == "n = length(words)"
    end
  end

  describe "reversed/1 → Enum.reverse" do
    test "with variable" do
      assert fix("reversed(items)", msg("reversed", 1)) == "Enum.reverse(items)"
    end

    test "in assignment" do
      assert fix("rev = reversed(list)", msg("reversed", 1)) == "rev = Enum.reverse(list)"
    end
  end

  # ── double-replacement safety ──────────────────────────────────

  describe "double-replacement safety" do
    test "two max/1 on same line" do
      assert fix("max([a, b]) + max([c, d])", msg("max", 1)) ==
               "Enum.max([a, b]) + Enum.max([c, d])"
    end

    test "idempotent for max" do
      source = "max([a, b]) + max([c, d])"
      once = fix(source, msg("max", 1))
      twice = fix(once, msg("max", 1))

      assert once == "Enum.max([a, b]) + Enum.max([c, d])"
      assert twice == once
    end

    test "two min/1 on same line" do
      assert fix("min([a, b]) + min([c, d])", msg("min", 1)) ==
               "Enum.min([a, b]) + Enum.min([c, d])"
    end

    test "idempotent for min" do
      source = "min(values)"
      once = fix(source, msg("min", 1))
      twice = fix(once, msg("min", 1))

      assert once == "Enum.min(values)"
      assert twice == once
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "local: no-ops" do
    test "unknown local function unchanged" do
      source = "foobar()"
      assert fix(source, msg("foobar", 0)) == source
    end

    test "max/2 not in replacements" do
      source = "max(a, b)"
      assert fix(source, msg("max", 2)) == source
    end

    test "min/2 not in replacements" do
      source = "min(a, b)"
      assert fix(source, msg("min", 2)) == source
    end
  end
end
