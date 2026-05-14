defmodule Credence.Semantic.UndefinedFunctionFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  # Qualified calls come from warnings
  defp fix_qualified(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  # Local calls come from errors
  defp fix_local(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  defp local_msg(name, arity) do
    "undefined function #{name}/#{arity} (expected MyModule to define such a function or for it to be imported, but none are available)"
  end

  # ╔═══════════════════════════════════════════════════════════════════╗
  # ║  QUALIFIED FIXES — Module.function renames                       ║
  # ╚═══════════════════════════════════════════════════════════════════╝

  describe "qualified: Enum.last → List.last" do
    test "direct call" do
      assert fix_qualified("Enum.last(list)", "Enum.last/1 is undefined or private") ==
               "List.last(list)"
    end

    test "piped" do
      assert fix_qualified("list |> Enum.last()", "Enum.last/0 is undefined or private") ==
               "list |> List.last()"
    end

    test "only on reported line" do
      input = "Enum.at(x, 0)\nEnum.last(x)\nEnum.count(x)"

      assert fix_qualified(input, "Enum.last/1 is undefined or private", 2) ==
               "Enum.at(x, 0)\nList.last(x)\nEnum.count(x)"
    end
  end

  describe "qualified: List.reverse → Enum.reverse" do
    test "direct call" do
      assert fix_qualified("List.reverse(items)", "List.reverse/1 is undefined or private") ==
               "Enum.reverse(items)"
    end

    test "piped" do
      assert fix_qualified("items |> List.reverse()", "List.reverse/1 is undefined or private") ==
               "items |> Enum.reverse()"
    end

    test "mid-pipeline" do
      assert fix_qualified(
               "nums |> Enum.sort() |> List.reverse() |> hd()",
               "List.reverse/1 is undefined or private"
             ) == "nums |> Enum.sort() |> Enum.reverse() |> hd()"
    end
  end

  describe "qualified: Enum.partition → Enum.split_with (deprecated)" do
    test "direct call" do
      assert fix_qualified(
               "Enum.partition(list, &is_integer/1)",
               "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead"
             ) == "Enum.split_with(list, &is_integer/1)"
    end

    test "piped" do
      assert fix_qualified(
               "list |> Enum.partition(fn {_v, i} -> Integer.is_even(i) end)",
               "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead"
             ) == "list |> Enum.split_with(fn {_v, i} -> Integer.is_even(i) end)"
    end

    test "only on reported line" do
      input = "x = Enum.map(list, &f/1)\n{a, b} = Enum.partition(list, &pred/1)"

      assert fix_qualified(
               input,
               "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead",
               2
             ) == "x = Enum.map(list, &f/1)\n{a, b} = Enum.split_with(list, &pred/1)"
    end
  end

  # ── qualified: hallucinated Float infinity ─────────────────────

  describe "qualified: Float.NegInfinity → :neg_infinity" do
    test "with parens" do
      assert fix_qualified("Float.NegInfinity()", "Float.NegInfinity/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "without parens" do
      assert fix_qualified("Float.NegInfinity", "Float.NegInfinity/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "as function argument" do
      assert fix_qualified(
               "validate(root, Float.NegInfinity(), Float.PositiveInfinity())",
               "Float.NegInfinity/0 is undefined or private"
             ) == "validate(root, :neg_infinity, Float.PositiveInfinity())"
    end
  end

  describe "qualified: Float.PositiveInfinity → :infinity" do
    test "with parens" do
      assert fix_qualified(
               "Float.PositiveInfinity()",
               "Float.PositiveInfinity/0 is undefined or private"
             ) == ":infinity"
    end

    test "without parens" do
      assert fix_qualified(
               "Float.PositiveInfinity",
               "Float.PositiveInfinity/0 is undefined or private"
             ) == ":infinity"
    end

    test "as function argument" do
      assert fix_qualified(
               "validate(root, :neg_infinity, Float.PositiveInfinity())",
               "Float.PositiveInfinity/0 is undefined or private"
             ) == "validate(root, :neg_infinity, :infinity)"
    end
  end

  describe "qualified: Float.NegInf → :neg_infinity" do
    test "direct call" do
      assert fix_qualified("Float.NegInf()", "Float.NegInf/0 is undefined or private") ==
               ":neg_infinity"
    end
  end

  describe "qualified: Float.Infinity → :infinity" do
    test "direct call" do
      assert fix_qualified("Float.Infinity()", "Float.Infinity/0 is undefined or private") ==
               ":infinity"
    end
  end

  describe "qualified: Float.inf → :infinity / -Float.inf → :neg_infinity" do
    test "negated without parens" do
      assert fix_qualified("max_num = -Float.inf", "Float.inf/0 is undefined or private") ==
               "max_num = :neg_infinity"
    end

    test "negated with parens" do
      assert fix_qualified("max_num = -Float.inf()", "Float.inf/0 is undefined or private") ==
               "max_num = :neg_infinity"
    end

    test "positive without parens" do
      assert fix_qualified("upper = Float.inf", "Float.inf/0 is undefined or private") ==
               "upper = :infinity"
    end

    test "positive with parens" do
      assert fix_qualified("upper = Float.inf()", "Float.inf/0 is undefined or private") ==
               "upper = :infinity"
    end

    test "realistic context" do
      code = "    max_num = -Float.inf\n    second_max_num = -Float.inf"

      assert fix_qualified(code, "Float.inf/0 is undefined or private", 1) ==
               "    max_num = :neg_infinity\n    second_max_num = -Float.inf"
    end
  end

  # ── qualified: hallucinated Integer bounds ──────────────────────

  describe "qualified: Integer.min_value → :neg_infinity" do
    test "with parens" do
      assert fix_qualified("Integer.min_value()", "Integer.min_value/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "without parens" do
      assert fix_qualified("Integer.min_value", "Integer.min_value/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "in module attribute" do
      assert fix_qualified(
               "@min_bound Integer.min_value()",
               "Integer.min_value/0 is undefined or private"
             ) == "@min_bound :neg_infinity"
    end
  end

  describe "qualified: Integer.max_value → :infinity" do
    test "with parens" do
      assert fix_qualified("Integer.max_value()", "Integer.max_value/0 is undefined or private") ==
               ":infinity"
    end

    test "without parens" do
      assert fix_qualified("Integer.max_value", "Integer.max_value/0 is undefined or private") ==
               ":infinity"
    end

    test "in module attribute" do
      assert fix_qualified(
               "@max_bound Integer.max_value()",
               "Integer.max_value/0 is undefined or private"
             ) == "@max_bound :infinity"
    end
  end

  # ── qualified: hallucinated List.pop ────────────────────────────

  describe "qualified: List.pop → List.last" do
    test "direct call" do
      assert fix_qualified("List.pop(items)", "List.pop/1 is undefined or private") ==
               "List.last(items)"
    end

    test "piped" do
      assert fix_qualified("items |> List.pop()", "List.pop/1 is undefined or private") ==
               "items |> List.last()"
    end

    test "mid-pipeline" do
      assert fix_qualified(
               "acc |> List.pop() |> elem(0)",
               "List.pop/1 is undefined or private"
             ) == "acc |> List.last() |> elem(0)"
    end
  end

  # ── qualified: wrong module ─────────────────────────────────────

  describe "qualified: List.drop → Enum.drop" do
    test "direct call" do
      assert fix_qualified("List.drop(items, 3)", "List.drop/2 is undefined or private") ==
               "Enum.drop(items, 3)"
    end

    test "piped" do
      assert fix_qualified("items |> List.drop(1)", "List.drop/2 is undefined or private") ==
               "items |> Enum.drop(1)"
    end

    test "nested" do
      assert fix_qualified(
               "List.last(sorted) * List.second(List.drop(sorted, n))",
               "List.drop/2 is undefined or private"
             ) == "List.last(sorted) * List.second(Enum.drop(sorted, n))"
    end
  end

  describe "qualified: Enum.cycle → Stream.cycle" do
    test "direct call" do
      assert fix_qualified("Enum.cycle(items)", "Enum.cycle/1 is undefined or private") ==
               "Stream.cycle(items)"
    end

    test "piped" do
      assert fix_qualified("items |> Enum.cycle()", "Enum.cycle/1 is undefined or private") ==
               "items |> Stream.cycle()"
    end

    test "inside expression" do
      assert fix_qualified(
               "Enum.flat_map(1..10, &Enum.cycle([&1]))",
               "Enum.cycle/1 is undefined or private"
             ) == "Enum.flat_map(1..10, &Stream.cycle([&1]))"
    end
  end

  # ── qualified: FunctionMatcher fallback ─────────────────────────

  describe "qualified: FunctionMatcher fallback — missing ? suffix" do
    test "Module.palindrome → Module.palindrome?" do
      source = """
      defmodule PalindromeChecker do
        def palindrome?(text), do: text == String.reverse(text)
        def run(text), do: PalindromeChecker.palindrome(text)
      end
      """

      expected = """
      defmodule PalindromeChecker do
        def palindrome?(text), do: text == String.reverse(text)
        def run(text), do: PalindromeChecker.palindrome?(text)
      end
      """

      assert fix_qualified(source, "PalindromeChecker.palindrome/1 is undefined or private", 3) ==
               expected
    end

    test "Module.valid → Module.valid?" do
      source = """
      defmodule Validator do
        def valid?(input), do: input != nil
        def check(input), do: Validator.valid(input)
      end
      """

      expected = """
      defmodule Validator do
        def valid?(input), do: input != nil
        def check(input), do: Validator.valid?(input)
      end
      """

      assert fix_qualified(source, "Validator.valid/1 is undefined or private", 3) == expected
    end
  end

  describe "qualified: FunctionMatcher fallback — prefix match" do
    test "Module.fib → closest defined function" do
      source = """
      defmodule Math do
        def fibonacci(n), do: n
        def run(n), do: Math.fib(n)
      end
      """

      expected = """
      defmodule Math do
        def fibonacci(n), do: n
        def run(n), do: Math.fibonacci(n)
      end
      """

      assert fix_qualified(source, "Math.fib/1 is undefined or private", 3) == expected
    end
  end

  describe "qualified: FunctionMatcher fallback — no candidates" do
    test "no matching-arity functions" do
      source = """
      defmodule Worker do
        def process(a, b), do: a + b
        def run, do: Worker.compute(42)
      end
      """

      assert fix_qualified(source, "Worker.compute/1 is undefined or private", 3) == source
    end

    test "module not found in source" do
      source = """
      defmodule Other do
        def run, do: Missing.foo(1)
      end
      """

      assert fix_qualified(source, "Missing.foo/1 is undefined or private", 2) == source
    end
  end

  describe "qualified: FunctionMatcher fallback — priority" do
    test "known replacement takes priority over FunctionMatcher" do
      source = """
      defmodule Example do
        def run(list), do: List.drop(list, 1)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.drop(list, 1)
      end
      """

      assert fix_qualified(source, "List.drop/2 is undefined or private", 2) == expected
    end
  end

  describe "qualified: FunctionMatcher fallback — visibility" do
    test "skips defp for module-qualified calls" do
      source = """
      defmodule Worker do
        defp helper(x), do: x * 2
        def run, do: Worker.help(42)
      end
      """

      assert fix_qualified(source, "Worker.help/1 is undefined or private", 3) == source
    end
  end

  # ── qualified: no-ops ──────────────────────────────────────────

  describe "qualified: no-ops" do
    test "unknown function unchanged" do
      source = "MyModule.foo(x)"
      assert fix_qualified(source, "MyModule.foo/1 is undefined or private") == source
    end

    test "unknown Float function unchanged" do
      source = "Float.unknown_thing()"
      assert fix_qualified(source, "Float.unknown_thing/0 is undefined or private") == source
    end
  end

  # ╔═══════════════════════════════════════════════════════════════════╗
  # ║  LOCAL FIXES — bare function calls                               ║
  # ╚═══════════════════════════════════════════════════════════════════╝

  # ── local: infinity → :math.inf() ──────────────────────────────

  describe "local: infinity() → :math.inf()" do
    test "standalone call" do
      assert fix_local("infinity()", local_msg("infinity", 0)) == ":math.inf()"
    end

    test "negated" do
      assert fix_local("-infinity()", local_msg("infinity", 0)) == "-:math.inf()"
    end

    test "in a tuple" do
      assert fix_local("{-infinity(), -infinity()}", local_msg("infinity", 0)) ==
               "{-:math.inf(), -:math.inf()}"
    end

    test "in Enum.reduce accumulator" do
      input = "Enum.reduce(nums, {-infinity(), -infinity()}, fn x, acc -> x end)"

      assert fix_local(input, local_msg("infinity", 0)) ==
               "Enum.reduce(nums, {-:math.inf(), -:math.inf()}, fn x, acc -> x end)"
    end

    test "only on reported line" do
      input = "x = infinity()\ny = infinity()"

      assert fix_local(input, local_msg("infinity", 0), 2) ==
               "x = infinity()\ny = :math.inf()"
    end
  end

  # ── local: max/1 → Enum.max ────────────────────────────────────

  describe "local: max/1 → Enum.max(list)" do
    test "with list literal" do
      assert fix_local("max([option1, option2])", local_msg("max", 1)) ==
               "Enum.max([option1, option2])"
    end

    test "with variable" do
      assert fix_local("max(values)", local_msg("max", 1)) == "Enum.max(values)"
    end

    test "in assignment" do
      assert fix_local("result = max([a, b, c])", local_msg("max", 1)) ==
               "result = Enum.max([a, b, c])"
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

      assert fix_local(code, local_msg("max", 1), 4) == expected
    end

    test "only on reported line" do
      input = "x = max(a, b)\ny = max([option1, option2])"

      assert fix_local(input, local_msg("max", 1), 2) ==
               "x = max(a, b)\ny = Enum.max([option1, option2])"
    end
  end

  # ── local: max/3,4,5 → Enum.max([...]) ─────────────────────────

  describe "local: max/3 → Enum.max([a, b, c])" do
    test "three simple args" do
      assert fix_local("max(a, b, c)", local_msg("max", 3)) == "Enum.max([a, b, c])"
    end

    test "in assignment" do
      assert fix_local("result = max(x, y, z)", local_msg("max", 3)) ==
               "result = Enum.max([x, y, z])"
    end

    test "with nested function call" do
      assert fix_local("max(foo(x), bar(y), z)", local_msg("max", 3)) ==
               "Enum.max([foo(x), bar(y), z])"
    end

    test "preserves inner Kernel.max/2" do
      assert fix_local("max(a, max(b, c), d)", local_msg("max", 3)) ==
               "Enum.max([a, max(b, c), d])"
    end
  end

  describe "local: max/4 → Enum.max([a, b, c, d])" do
    test "four simple args" do
      assert fix_local("max(a, b, c, d)", local_msg("max", 4)) == "Enum.max([a, b, c, d])"
    end
  end

  describe "local: max/5 → Enum.max([a, b, c, d, e])" do
    test "five simple args" do
      assert fix_local("max(a, b, c, d, e)", local_msg("max", 5)) ==
               "Enum.max([a, b, c, d, e])"
    end
  end

  # ── local: min/1 → Enum.min ────────────────────────────────────

  describe "local: min/1 → Enum.min(list)" do
    test "with list literal" do
      assert fix_local("min([a, b])", local_msg("min", 1)) == "Enum.min([a, b])"
    end

    test "with variable" do
      assert fix_local("min(values)", local_msg("min", 1)) == "Enum.min(values)"
    end

    test "in assignment" do
      assert fix_local("lowest = min([x, y, z])", local_msg("min", 1)) ==
               "lowest = Enum.min([x, y, z])"
    end
  end

  # ── local: min/3,4,5 → Enum.min([...]) ─────────────────────────

  describe "local: min/3 → Enum.min([a, b, c])" do
    test "three simple args" do
      assert fix_local("min(a, b, c)", local_msg("min", 3)) == "Enum.min([a, b, c])"
    end

    test "with nested function call" do
      assert fix_local("min(foo(x), bar(y), z)", local_msg("min", 3)) ==
               "Enum.min([foo(x), bar(y), z])"
    end

    test "preserves inner Kernel.min/2" do
      assert fix_local("min(a, min(b, c), d)", local_msg("min", 3)) ==
               "Enum.min([a, min(b, c), d])"
    end
  end

  describe "local: min/4 → Enum.min([a, b, c, d])" do
    test "four simple args" do
      assert fix_local("min(a, b, c, d)", local_msg("min", 4)) == "Enum.min([a, b, c, d])"
    end
  end

  describe "local: min/5 → Enum.min([a, b, c, d, e])" do
    test "five simple args" do
      assert fix_local("min(a, b, c, d, e)", local_msg("min", 5)) ==
               "Enum.min([a, b, c, d, e])"
    end
  end

  # ── local: Python built-ins ─────────────────────────────────────

  describe "local: sum/1 → Enum.sum" do
    test "with variable" do
      assert fix_local("sum(numbers)", local_msg("sum", 1)) == "Enum.sum(numbers)"
    end

    test "with list literal" do
      assert fix_local("sum([1, 2, 3])", local_msg("sum", 1)) == "Enum.sum([1, 2, 3])"
    end

    test "in assignment" do
      assert fix_local("total = sum(values)", local_msg("sum", 1)) == "total = Enum.sum(values)"
    end
  end

  describe "local: sorted/1 → Enum.sort" do
    test "with variable" do
      assert fix_local("sorted(numbers)", local_msg("sorted", 1)) == "Enum.sort(numbers)"
    end

    test "in pipeline" do
      assert fix_local("result = sorted(items) |> Enum.take(5)", local_msg("sorted", 1)) ==
               "result = Enum.sort(items) |> Enum.take(5)"
    end
  end

  describe "local: len/1 → length" do
    test "with variable" do
      assert fix_local("len(items)", local_msg("len", 1)) == "length(items)"
    end

    test "in comparison" do
      assert fix_local("if len(list) > 0, do: :ok", local_msg("len", 1)) ==
               "if length(list) > 0, do: :ok"
    end

    test "in assignment" do
      assert fix_local("n = len(words)", local_msg("len", 1)) == "n = length(words)"
    end
  end

  describe "local: reversed/1 → Enum.reverse" do
    test "with variable" do
      assert fix_local("reversed(items)", local_msg("reversed", 1)) == "Enum.reverse(items)"
    end

    test "in assignment" do
      assert fix_local("rev = reversed(list)", local_msg("reversed", 1)) ==
               "rev = Enum.reverse(list)"
    end
  end

  # ── local: range ────────────────────────────────────────────────

  describe "local: range/1 → 0..n - 1" do
    test "literal integer" do
      assert fix_local("range(10)", local_msg("range", 1)) == "0..10 - 1"
    end

    test "variable" do
      assert fix_local("range(n)", local_msg("range", 1)) == "0..n - 1"
    end

    test "function call as arg" do
      assert fix_local("range(length(list))", local_msg("range", 1)) == "0..length(list) - 1"
    end

    test "in assignment" do
      assert fix_local("nums = range(10)", local_msg("range", 1)) == "nums = 0..10 - 1"
    end

    test "inside Enum.to_list" do
      assert fix_local("Enum.to_list(range(5))", local_msg("range", 1)) ==
               "Enum.to_list(0..5 - 1)"
    end

    test "inside Enum.map" do
      assert fix_local("Enum.map(range(n), &to_string/1)", local_msg("range", 1)) ==
               "Enum.map(0..n - 1, &to_string/1)"
    end
  end

  describe "local: range/2 → a..b - 1" do
    test "two literals" do
      assert fix_local("range(0, 10)", local_msg("range", 2)) == "0..10 - 1"
    end

    test "two variables" do
      assert fix_local("range(start, stop)", local_msg("range", 2)) == "start..stop - 1"
    end

    test "start at 1" do
      assert fix_local("range(1, n)", local_msg("range", 2)) == "1..n - 1"
    end

    test "function call as stop" do
      assert fix_local("range(0, length(list))", local_msg("range", 2)) ==
               "0..length(list) - 1"
    end

    test "in assignment" do
      assert fix_local("indices = range(0, n)", local_msg("range", 2)) == "indices = 0..n - 1"
    end

    test "inside Enum.each" do
      assert fix_local("Enum.each(range(1, 10), &IO.puts/1)", local_msg("range", 2)) ==
               "Enum.each(1..10 - 1, &IO.puts/1)"
    end
  end

  describe "local: range/3 → a..b//c" do
    test "positive step" do
      assert fix_local("range(0, 10, 2)", local_msg("range", 3)) == "0..10//2"
    end

    test "negative step" do
      assert fix_local("range(10, 0, -1)", local_msg("range", 3)) == "10..0//-1"
    end

    test "negative step -2" do
      assert fix_local("range(10, 0, -2)", local_msg("range", 3)) == "10..0//-2"
    end

    test "all variables" do
      assert fix_local("range(a, b, step)", local_msg("range", 3)) == "a..b//step"
    end

    test "the actual LLM log case" do
      assert fix_local("range(max_num, min_num - 1, -1)", local_msg("range", 3)) ==
               "max_num..min_num - 1//-1"
    end

    test "with nested function calls" do
      assert fix_local("range(length(a), length(b), 1)", local_msg("range", 3)) ==
               "length(a)..length(b)//1"
    end

    test "arithmetic in start" do
      assert fix_local("range(n - 1, 0, -1)", local_msg("range", 3)) == "n - 1..0//-1"
    end
  end

  describe "local: range — realistic contexts" do
    test "in Enum.reduce_while" do
      assert fix_local(
               "Enum.reduce_while(range(max_num, min_num - 1, -1), nil, fn i, _ ->",
               local_msg("range", 3)
             ) == "Enum.reduce_while(max_num..min_num - 1//-1, nil, fn i, _ ->"
    end

    test "in assignment" do
      assert fix_local("nums = range(10, 0, -1)", local_msg("range", 3)) == "nums = 10..0//-1"
    end

    test "piped into Enum.map" do
      assert fix_local("range(0, 10, 2) |> Enum.map(&(&1 * 2))", local_msg("range", 3)) ==
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

      assert fix_local(input, local_msg("range", 3), 6) == expected
    end

    test "only fixes reported line" do
      input = "x = Enum.to_list(1..10)\ny = range(0, 5)"

      assert fix_local(input, local_msg("range", 2), 2) == "x = Enum.to_list(1..10)\ny = 0..5 - 1"
    end
  end

  # ── local: FunctionMatcher fallback ─────────────────────────────

  describe "local: FunctionMatcher fallback — missing ? suffix" do
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

      assert fix_local(
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

      assert fix_local(
               source,
               "undefined function even/1 (expected Math to define such a function or for it to be imported, but none are available)",
               3
             ) == expected
    end
  end

  describe "local: FunctionMatcher fallback — __ demangle" do
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

      assert fix_local(
               source,
               "undefined function perfect__/1 (expected PerfectNumbers to define such a function or for it to be imported, but none are available)",
               3
             ) == expected
    end
  end

  describe "local: FunctionMatcher fallback — prefix/substring" do
    test "fibonacci → fib" do
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

      assert fix_local(
               source,
               "undefined function fibonacci/1 (expected Fibonacci to define such a function or for it to be imported, but none are available)",
               5
             ) == expected
    end
  end

  describe "local: FunctionMatcher fallback — sole candidate" do
    test "picks the only arity-matching function" do
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

      assert fix_local(
               source,
               "undefined function calculate/1 (expected Calculator to define such a function or for it to be imported, but none are available)",
               4
             ) == expected
    end
  end

  describe "local: FunctionMatcher fallback — no candidates" do
    test "no matching-arity functions" do
      source = """
      defmodule Worker do
        def process(a, b), do: a + b
        def run, do: compute(42)
      end
      """

      assert fix_local(
               source,
               "undefined function compute/1 (expected Worker to define such a function or for it to be imported, but none are available)",
               3
             ) == source
    end

    test "module not found" do
      source = """
      defmodule Other do
        def run, do: something(1)
      end
      """

      assert fix_local(
               source,
               "undefined function something/1 (expected Missing to define such a function or for it to be imported, but none are available)",
               2
             ) == source
    end

    test "module name not in error message" do
      source = "fibonacci(5)"
      assert fix_local(source, "undefined function fibonacci/1", 1) == source
    end
  end

  describe "local: FunctionMatcher fallback — includes defp" do
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

      assert fix_local(
               source,
               "undefined function help/1 (expected Worker to define such a function or for it to be imported, but none are available)",
               3
             ) == expected
    end
  end

  describe "local: FunctionMatcher fallback — priority" do
    test "known replacement takes priority over FunctionMatcher" do
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

      assert fix_local(source, local_msg("max", 1), 3) == expected
    end
  end

  # ── local: double-replacement safety ────────────────────────────

  describe "local: double-replacement safety" do
    test "two max/1 on same line" do
      assert fix_local("max([a, b]) + max([c, d])", local_msg("max", 1)) ==
               "Enum.max([a, b]) + Enum.max([c, d])"
    end

    test "idempotent for max" do
      source = "max([a, b]) + max([c, d])"
      once = fix_local(source, local_msg("max", 1))
      twice = fix_local(once, local_msg("max", 1))

      assert once == "Enum.max([a, b]) + Enum.max([c, d])"
      assert twice == once
    end

    test "two min/1 on same line" do
      assert fix_local("min([a, b]) + min([c, d])", local_msg("min", 1)) ==
               "Enum.min([a, b]) + Enum.min([c, d])"
    end

    test "idempotent for min" do
      source = "min(values)"
      once = fix_local(source, local_msg("min", 1))
      twice = fix_local(once, local_msg("min", 1))

      assert once == "Enum.min(values)"
      assert twice == once
    end
  end

  # ── local: no-ops ───────────────────────────────────────────────

  describe "local: no-ops" do
    test "unknown local function unchanged" do
      source = "foobar()"
      assert fix_local(source, local_msg("foobar", 0)) == source
    end

    test "max/2 not in replacements" do
      source = "max(a, b)"
      assert fix_local(source, local_msg("max", 2)) == source
    end

    test "min/2 not in replacements" do
      source = "min(a, b)"
      assert fix_local(source, local_msg("min", 2)) == source
    end
  end
end
