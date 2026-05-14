defmodule Credence.Semantic.UndefinedLocalFunctionFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedLocalFunction

  defp fix(source, message, line \\ 1) do
    UndefinedLocalFunction.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  defp msg(name, arity) do
    "undefined function #{name}/#{arity} (expected MyModule to define such a function or for it to be imported, but none are available)"
  end

  # ═══════════════════════════════════════════════════════════════════
  # infinity() → :math.inf()
  # ═══════════════════════════════════════════════════════════════════

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

      assert fix(input, msg("infinity", 0), 2) ==
               "x = infinity()\ny = :math.inf()"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # max/1 — max(list) → Enum.max(list)
  # ═══════════════════════════════════════════════════════════════════

  describe "max/1 → Enum.max(list)" do
    test "with list literal" do
      assert fix("max([option1, option2])", msg("max", 1)) ==
               "Enum.max([option1, option2])"
    end

    test "with variable" do
      assert fix("max(values)", msg("max", 1)) ==
               "Enum.max(values)"
    end

    test "in assignment" do
      assert fix("result = max([a, b, c])", msg("max", 1)) ==
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

      assert fix(code, msg("max", 1), 4) == expected
    end

    test "only on reported line" do
      input = "x = max(a, b)\ny = max([option1, option2])"

      assert fix(input, msg("max", 1), 2) ==
               "x = max(a, b)\ny = Enum.max([option1, option2])"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # max/3,4,5 — max(a, b, c) → Enum.max([a, b, c])
  # ═══════════════════════════════════════════════════════════════════

  describe "max/3 → Enum.max([a, b, c])" do
    test "three simple args" do
      assert fix("max(a, b, c)", msg("max", 3)) ==
               "Enum.max([a, b, c])"
    end

    test "in assignment" do
      assert fix("result = max(x, y, z)", msg("max", 3)) ==
               "result = Enum.max([x, y, z])"
    end

    test "with nested function call in args" do
      assert fix("max(foo(x), bar(y), z)", msg("max", 3)) ==
               "Enum.max([foo(x), bar(y), z])"
    end

    test "preserves inner Kernel.max/2" do
      assert fix("max(a, max(b, c), d)", msg("max", 3)) ==
               "Enum.max([a, max(b, c), d])"
    end
  end

  describe "max/4 → Enum.max([a, b, c, d])" do
    test "four simple args" do
      assert fix("max(a, b, c, d)", msg("max", 4)) ==
               "Enum.max([a, b, c, d])"
    end
  end

  describe "max/5 → Enum.max([a, b, c, d, e])" do
    test "five simple args" do
      assert fix("max(a, b, c, d, e)", msg("max", 5)) ==
               "Enum.max([a, b, c, d, e])"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # min/1 — min(list) → Enum.min(list)
  # ═══════════════════════════════════════════════════════════════════

  describe "min/1 → Enum.min(list)" do
    test "with list literal" do
      assert fix("min([a, b])", msg("min", 1)) ==
               "Enum.min([a, b])"
    end

    test "with variable" do
      assert fix("min(values)", msg("min", 1)) ==
               "Enum.min(values)"
    end

    test "in assignment" do
      assert fix("lowest = min([x, y, z])", msg("min", 1)) ==
               "lowest = Enum.min([x, y, z])"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # min/3,4,5 — min(a, b, c) → Enum.min([a, b, c])
  # ═══════════════════════════════════════════════════════════════════

  describe "min/3 → Enum.min([a, b, c])" do
    test "three simple args" do
      assert fix("min(a, b, c)", msg("min", 3)) ==
               "Enum.min([a, b, c])"
    end

    test "with nested function call" do
      assert fix("min(foo(x), bar(y), z)", msg("min", 3)) ==
               "Enum.min([foo(x), bar(y), z])"
    end

    test "preserves inner Kernel.min/2" do
      assert fix("min(a, min(b, c), d)", msg("min", 3)) ==
               "Enum.min([a, min(b, c), d])"
    end
  end

  describe "min/4 → Enum.min([a, b, c, d])" do
    test "four simple args" do
      assert fix("min(a, b, c, d)", msg("min", 4)) ==
               "Enum.min([a, b, c, d])"
    end
  end

  describe "min/5 → Enum.min([a, b, c, d, e])" do
    test "five simple args" do
      assert fix("min(a, b, c, d, e)", msg("min", 5)) ==
               "Enum.min([a, b, c, d, e])"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # sum/1 — sum(list) → Enum.sum(list)
  # ═══════════════════════════════════════════════════════════════════

  describe "sum/1 → Enum.sum(list)" do
    test "with variable" do
      assert fix("sum(numbers)", msg("sum", 1)) ==
               "Enum.sum(numbers)"
    end

    test "with list literal" do
      assert fix("sum([1, 2, 3])", msg("sum", 1)) ==
               "Enum.sum([1, 2, 3])"
    end

    test "in assignment" do
      assert fix("total = sum(values)", msg("sum", 1)) ==
               "total = Enum.sum(values)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # sorted/1 — sorted(list) → Enum.sort(list)
  # ═══════════════════════════════════════════════════════════════════

  describe "sorted/1 → Enum.sort(list)" do
    test "with variable" do
      assert fix("sorted(numbers)", msg("sorted", 1)) ==
               "Enum.sort(numbers)"
    end

    test "in pipeline" do
      assert fix("result = sorted(items) |> Enum.take(5)", msg("sorted", 1)) ==
               "result = Enum.sort(items) |> Enum.take(5)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # len/1 — len(list) → length(list)
  # ═══════════════════════════════════════════════════════════════════

  describe "len/1 → length(list)" do
    test "with variable" do
      assert fix("len(items)", msg("len", 1)) ==
               "length(items)"
    end

    test "in comparison" do
      assert fix("if len(list) > 0, do: :ok", msg("len", 1)) ==
               "if length(list) > 0, do: :ok"
    end

    test "in assignment" do
      assert fix("n = len(words)", msg("len", 1)) ==
               "n = length(words)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # reversed/1 — reversed(list) → Enum.reverse(list)
  # ═══════════════════════════════════════════════════════════════════

  describe "reversed/1 → Enum.reverse(list)" do
    test "with variable" do
      assert fix("reversed(items)", msg("reversed", 1)) ==
               "Enum.reverse(items)"
    end

    test "in assignment" do
      assert fix("rev = reversed(list)", msg("reversed", 1)) ==
               "rev = Enum.reverse(list)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # range/1 — range(n) → 0..n - 1
  # ═══════════════════════════════════════════════════════════════════

  describe "range/1 → 0..n - 1" do
    test "literal integer" do
      assert fix("range(10)", msg("range", 1)) == "0..10 - 1"
    end

    test "variable" do
      assert fix("range(n)", msg("range", 1)) == "0..n - 1"
    end

    test "function call as arg" do
      assert fix("range(length(list))", msg("range", 1)) == "0..length(list) - 1"
    end

    test "in assignment" do
      assert fix("nums = range(10)", msg("range", 1)) == "nums = 0..10 - 1"
    end

    test "inside Enum.to_list" do
      assert fix("Enum.to_list(range(5))", msg("range", 1)) == "Enum.to_list(0..5 - 1)"
    end

    test "inside Enum.map" do
      assert fix("Enum.map(range(n), &to_string/1)", msg("range", 1)) ==
               "Enum.map(0..n - 1, &to_string/1)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # range/2 — range(a, b) → a..b - 1
  # ═══════════════════════════════════════════════════════════════════

  describe "range/2 → a..b - 1" do
    test "two literals" do
      assert fix("range(0, 10)", msg("range", 2)) == "0..10 - 1"
    end

    test "two variables" do
      assert fix("range(start, stop)", msg("range", 2)) == "start..stop - 1"
    end

    test "start at 1" do
      assert fix("range(1, n)", msg("range", 2)) == "1..n - 1"
    end

    test "function call as stop" do
      assert fix("range(0, length(list))", msg("range", 2)) == "0..length(list) - 1"
    end

    test "in assignment" do
      assert fix("indices = range(0, n)", msg("range", 2)) == "indices = 0..n - 1"
    end

    test "inside Enum.each" do
      assert fix("Enum.each(range(1, 10), &IO.puts/1)", msg("range", 2)) ==
               "Enum.each(1..10 - 1, &IO.puts/1)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # range/3 — range(a, b, c) → a..b//c  (naive, no stop adjustment)
  # ═══════════════════════════════════════════════════════════════════

  describe "range/3 → a..b//c" do
    test "positive step" do
      assert fix("range(0, 10, 2)", msg("range", 3)) == "0..10//2"
    end

    test "negative step" do
      assert fix("range(10, 0, -1)", msg("range", 3)) == "10..0//-1"
    end

    test "negative step -2" do
      assert fix("range(10, 0, -2)", msg("range", 3)) == "10..0//-2"
    end

    test "all variables" do
      assert fix("range(a, b, step)", msg("range", 3)) == "a..b//step"
    end

    test "the actual LLM log case" do
      assert fix("range(max_num, min_num - 1, -1)", msg("range", 3)) ==
               "max_num..min_num - 1//-1"
    end

    test "with nested function calls" do
      assert fix("range(length(a), length(b), 1)", msg("range", 3)) ==
               "length(a)..length(b)//1"
    end

    test "arithmetic in start" do
      assert fix("range(n - 1, 0, -1)", msg("range", 3)) == "n - 1..0//-1"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # range — realistic contexts
  # ═══════════════════════════════════════════════════════════════════

  describe "range — realistic contexts" do
    test "in Enum.reduce_while (the actual log case)" do
      assert fix(
               "Enum.reduce_while(range(max_num, min_num - 1, -1), nil, fn i, _ ->",
               msg("range", 3)
             ) == "Enum.reduce_while(max_num..min_num - 1//-1, nil, fn i, _ ->"
    end

    test "in assignment" do
      assert fix("nums = range(10, 0, -1)", msg("range", 3)) == "nums = 10..0//-1"
    end

    test "piped into Enum.map" do
      assert fix("range(0, 10, 2) |> Enum.map(&(&1 * 2))", msg("range", 3)) ==
               "0..10//2 |> Enum.map(&(&1 * 2))"
    end

    test "preserves surrounding code" do
      input = """
      defmodule Palindrome do
        def largest(n) do
          max_num = Integer.pow(10, n) - 1
          min_num = Integer.pow(10, n - 1)

          Enum.reduce_while(range(max_num, min_num - 1, -1), 0, fn i, acc ->
            {:cont, max(acc, i)}
          end)
        end
      end
      """

      expected = """
      defmodule Palindrome do
        def largest(n) do
          max_num = Integer.pow(10, n) - 1
          min_num = Integer.pow(10, n - 1)

          Enum.reduce_while(max_num..min_num - 1//-1, 0, fn i, acc ->
            {:cont, max(acc, i)}
          end)
        end
      end
      """

      assert fix(input, msg("range", 3), 6) == expected
    end

    test "only fixes reported line" do
      input = "x = Enum.to_list(1..10)\ny = range(0, 5)"

      assert fix(input, msg("range", 2), 2) == "x = Enum.to_list(1..10)\ny = 0..5 - 1"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FUNCTION MATCHER FALLBACK — missing ? suffix
  # ═══════════════════════════════════════════════════════════════════

  describe "FunctionMatcher fallback — missing ? suffix" do
    test "palindrome → palindrome?" do
      source = """
      defmodule PalindromeChecker do
        def palindrome?(text), do: text == String.reverse(text)
        def run(text), do: palindrome(text)
      end
      """

      expected = """
      defmodule PalindromeChecker do
        def palindrome?(text), do: text == String.reverse(text)
        def run(text), do: palindrome?(text)
      end
      """

      assert fix(
               source,
               "undefined function palindrome/1 (expected PalindromeChecker to define such a function or for it to be imported, but none are available)",
               3
             ) == expected
    end

    test "even → even?" do
      source = """
      defmodule Math do
        def even?(n), do: rem(n, 2) == 0
        def check(n), do: even(n)
      end
      """

      expected = """
      defmodule Math do
        def even?(n), do: rem(n, 2) == 0
        def check(n), do: even?(n)
      end
      """

      assert fix(
               source,
               "undefined function even/1 (expected Math to define such a function or for it to be imported, but none are available)",
               3
             ) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FUNCTION MATCHER FALLBACK — __ demangle
  # ═══════════════════════════════════════════════════════════════════

  describe "FunctionMatcher fallback — __ demangle" do
    test "perfect__ → perfect?" do
      source = """
      defmodule PerfectNumbers do
        def perfect?(n), do: n == 6
        def check(n), do: perfect__(n)
      end
      """

      expected = """
      defmodule PerfectNumbers do
        def perfect?(n), do: n == 6
        def check(n), do: perfect?(n)
      end
      """

      assert fix(
               source,
               "undefined function perfect__/1 (expected PerfectNumbers to define such a function or for it to be imported, but none are available)",
               3
             ) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FUNCTION MATCHER FALLBACK — prefix/substring match
  # ═══════════════════════════════════════════════════════════════════

  describe "FunctionMatcher fallback — prefix/substring" do
    test "fibonacci → fib (candidate is prefix of undefined name)" do
      source = """
      defmodule Fibonacci do
        def fib(0), do: 0
        def fib(1), do: 1
        def fib(n), do: fib(n - 1) + fib(n - 2)
        def run(n), do: fibonacci(n)
      end
      """

      expected = """
      defmodule Fibonacci do
        def fib(0), do: 0
        def fib(1), do: 1
        def fib(n), do: fib(n - 1) + fib(n - 2)
        def run(n), do: fib(n)
      end
      """

      assert fix(
               source,
               "undefined function fibonacci/1 (expected Fibonacci to define such a function or for it to be imported, but none are available)",
               5
             ) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FUNCTION MATCHER FALLBACK — sole candidate
  # ═══════════════════════════════════════════════════════════════════

  describe "FunctionMatcher fallback — sole candidate" do
    test "picks the only arity-matching function even with unrelated name" do
      source = """
      defmodule Calculator do
        def compute(n), do: n * 2
        def add(a, b), do: a + b
        def run(n), do: calculate(n)
      end
      """

      expected = """
      defmodule Calculator do
        def compute(n), do: n * 2
        def add(a, b), do: a + b
        def run(n), do: compute(n)
      end
      """

      assert fix(
               source,
               "undefined function calculate/1 (expected Calculator to define such a function or for it to be imported, but none are available)",
               4
             ) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FUNCTION MATCHER FALLBACK — no candidates / edge cases
  # ═══════════════════════════════════════════════════════════════════

  describe "FunctionMatcher fallback — no candidates" do
    test "returns source unchanged when no matching-arity functions exist" do
      source = """
      defmodule Worker do
        def process(a, b), do: a + b
        def run, do: compute(42)
      end
      """

      assert fix(
               source,
               "undefined function compute/1 (expected Worker to define such a function or for it to be imported, but none are available)",
               3
             ) == source
    end

    test "returns source unchanged when module not found" do
      source = """
      defmodule Other do
        def run, do: something(1)
      end
      """

      assert fix(
               source,
               "undefined function something/1 (expected Missing to define such a function or for it to be imported, but none are available)",
               2
             ) == source
    end

    test "returns source unchanged when module name not in error message" do
      source = "fibonacci(5)"

      assert fix(source, "undefined function fibonacci/1", 1) == source
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FUNCTION MATCHER FALLBACK — includes defp for local calls
  # ═══════════════════════════════════════════════════════════════════

  describe "FunctionMatcher fallback — includes defp" do
    test "finds defp functions for local calls" do
      source = """
      defmodule Worker do
        defp helper(x), do: x * 2
        def run(x), do: help(x)
      end
      """

      expected = """
      defmodule Worker do
        defp helper(x), do: x * 2
        def run(x), do: helper(x)
      end
      """

      assert fix(
               source,
               "undefined function help/1 (expected Worker to define such a function or for it to be imported, but none are available)",
               3
             ) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FUNCTION MATCHER FALLBACK — known replacement takes priority
  # ═══════════════════════════════════════════════════════════════════

  describe "FunctionMatcher fallback — known replacement takes priority" do
    test "max/1 uses hardcoded Enum.max rename, not FunctionMatcher" do
      source = """
      defmodule Example do
        def compute(list), do: list
        def run(list), do: max(list)
      end
      """

      expected = """
      defmodule Example do
        def compute(list), do: list
        def run(list), do: Enum.max(list)
      end
      """

      assert fix(source, msg("max", 1), 3) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOUBLE-REPLACEMENT SAFETY
  # ═══════════════════════════════════════════════════════════════════

  describe "double-replacement safety" do
    test "two max/1 on same line — first fix handles both" do
      assert fix("max([a, b]) + max([c, d])", msg("max", 1)) ==
               "Enum.max([a, b]) + Enum.max([c, d])"
    end

    test "idempotent — second fix on already-fixed line is harmless" do
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

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS
  # ═══════════════════════════════════════════════════════════════════

  describe "no-ops" do
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
