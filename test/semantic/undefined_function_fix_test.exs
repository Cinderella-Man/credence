defmodule Credence.Semantic.UndefinedFunctionFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  # ── module.function renames (existing) ─────────────────────────

  describe "Enum.last → List.last" do
    test "direct call" do
      assert fix("Enum.last(list)", "Enum.last/1 is undefined or private") == "List.last(list)"
    end

    test "piped" do
      assert fix("list |> Enum.last()", "Enum.last/0 is undefined or private") ==
               "list |> List.last()"
    end

    test "only on reported line" do
      input = "Enum.at(x, 0)\nEnum.last(x)\nEnum.count(x)"

      assert fix(input, "Enum.last/1 is undefined or private", 2) ==
               "Enum.at(x, 0)\nList.last(x)\nEnum.count(x)"
    end
  end

  describe "List.reverse → Enum.reverse" do
    test "direct call" do
      assert fix("List.reverse(items)", "List.reverse/1 is undefined or private") ==
               "Enum.reverse(items)"
    end

    test "piped" do
      assert fix("items |> List.reverse()", "List.reverse/1 is undefined or private") ==
               "items |> Enum.reverse()"
    end

    test "mid-pipeline" do
      assert fix(
               "nums |> Enum.sort() |> List.reverse() |> hd()",
               "List.reverse/1 is undefined or private"
             ) ==
               "nums |> Enum.sort() |> Enum.reverse() |> hd()"
    end
  end

  describe "Enum.partition → Enum.split_with (deprecated)" do
    test "direct call" do
      assert fix(
               "Enum.partition(list, &is_integer/1)",
               "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead"
             ) == "Enum.split_with(list, &is_integer/1)"
    end

    test "piped" do
      assert fix(
               "list |> Enum.partition(fn {_v, i} -> Integer.is_even(i) end)",
               "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead"
             ) == "list |> Enum.split_with(fn {_v, i} -> Integer.is_even(i) end)"
    end

    test "only on reported line" do
      input = "x = Enum.map(list, &f/1)\n{a, b} = Enum.partition(list, &pred/1)"

      assert fix(input, "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead", 2) ==
               "x = Enum.map(list, &f/1)\n{a, b} = Enum.split_with(list, &pred/1)"
    end
  end

  # ── hallucinated Float infinity → atom literals ────────────────

  describe "Float.NegInfinity() → :neg_infinity" do
    test "direct call with parens" do
      assert fix("Float.NegInfinity()", "Float.NegInfinity/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "direct call without parens" do
      assert fix("Float.NegInfinity", "Float.NegInfinity/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "as function argument" do
      assert fix(
               "validate(root, Float.NegInfinity(), Float.PositiveInfinity())",
               "Float.NegInfinity/0 is undefined or private"
             ) == "validate(root, :neg_infinity, Float.PositiveInfinity())"
    end
  end

  describe "Float.PositiveInfinity() → :infinity" do
    test "direct call with parens" do
      assert fix("Float.PositiveInfinity()", "Float.PositiveInfinity/0 is undefined or private") ==
               ":infinity"
    end

    test "direct call without parens" do
      assert fix("Float.PositiveInfinity", "Float.PositiveInfinity/0 is undefined or private") ==
               ":infinity"
    end

    test "as function argument" do
      assert fix(
               "validate(root, :neg_infinity, Float.PositiveInfinity())",
               "Float.PositiveInfinity/0 is undefined or private"
             ) == "validate(root, :neg_infinity, :infinity)"
    end
  end

  describe "Float.NegInf() → :neg_infinity" do
    test "direct call" do
      assert fix("Float.NegInf()", "Float.NegInf/0 is undefined or private") == ":neg_infinity"
    end
  end

  describe "Float.Infinity() → :infinity" do
    test "direct call" do
      assert fix("Float.Infinity()", "Float.Infinity/0 is undefined or private") == ":infinity"
    end
  end

  # ── Float.inf (lowercase, often negated) ───────────────────────

  describe "Float.inf → :infinity / -Float.inf → :neg_infinity" do
    test "negated without parens (the actual LLM pattern)" do
      assert fix("max_num = -Float.inf", "Float.inf/0 is undefined or private") ==
               "max_num = :neg_infinity"
    end

    test "negated with parens" do
      assert fix("max_num = -Float.inf()", "Float.inf/0 is undefined or private") ==
               "max_num = :neg_infinity"
    end

    test "positive without parens" do
      assert fix("upper = Float.inf", "Float.inf/0 is undefined or private") ==
               "upper = :infinity"
    end

    test "positive with parens" do
      assert fix("upper = Float.inf()", "Float.inf/0 is undefined or private") ==
               "upper = :infinity"
    end

    test "realistic context from LLM log" do
      code = "    max_num = -Float.inf\n    second_max_num = -Float.inf"

      assert fix(code, "Float.inf/0 is undefined or private", 1) ==
               "    max_num = :neg_infinity\n    second_max_num = -Float.inf"
    end
  end

  # ── hallucinated Integer bounds → atom literals ────────────────

  describe "Integer.min_value() → :neg_infinity" do
    test "direct call" do
      assert fix("Integer.min_value()", "Integer.min_value/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "without parens" do
      assert fix("Integer.min_value", "Integer.min_value/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "in module attribute" do
      assert fix("@min_bound Integer.min_value()", "Integer.min_value/0 is undefined or private") ==
               "@min_bound :neg_infinity"
    end
  end

  describe "Integer.max_value() → :infinity" do
    test "direct call" do
      assert fix("Integer.max_value()", "Integer.max_value/0 is undefined or private") ==
               ":infinity"
    end

    test "without parens" do
      assert fix("Integer.max_value", "Integer.max_value/0 is undefined or private") ==
               ":infinity"
    end

    test "in module attribute" do
      assert fix("@max_bound Integer.max_value()", "Integer.max_value/0 is undefined or private") ==
               "@max_bound :infinity"
    end
  end

  # ── hallucinated List.pop → List.last ──────────────────────────

  describe "List.pop → List.last" do
    test "direct call" do
      assert fix("List.pop(items)", "List.pop/1 is undefined or private") == "List.last(items)"
    end

    test "piped" do
      assert fix("items |> List.pop()", "List.pop/1 is undefined or private") ==
               "items |> List.last()"
    end

    test "mid-pipeline" do
      assert fix(
               "acc |> List.pop() |> elem(0)",
               "List.pop/1 is undefined or private"
             ) == "acc |> List.last() |> elem(0)"
    end
  end

  # ── List.drop → Enum.drop ───────────────────────────────────────

  describe "List.drop → Enum.drop" do
    test "direct call" do
      assert fix("List.drop(items, 3)", "List.drop/2 is undefined or private") ==
               "Enum.drop(items, 3)"
    end

    test "piped" do
      assert fix("items |> List.drop(1)", "List.drop/2 is undefined or private") ==
               "items |> Enum.drop(1)"
    end

    test "nested in expression" do
      assert fix(
               "List.last(sorted) * List.second(List.drop(sorted, n))",
               "List.drop/2 is undefined or private"
             ) ==
               "List.last(sorted) * List.second(Enum.drop(sorted, n))"
    end
  end

  # ── Enum.cycle → Stream.cycle ──────────────────────────────────

  describe "Enum.cycle → Stream.cycle" do
    test "direct call" do
      assert fix("Enum.cycle(items)", "Enum.cycle/1 is undefined or private") ==
               "Stream.cycle(items)"
    end

    test "piped" do
      assert fix("items |> Enum.cycle()", "Enum.cycle/1 is undefined or private") ==
               "items |> Stream.cycle()"
    end

    test "inside expression" do
      assert fix(
               "Enum.flat_map(1..10, &Enum.cycle([&1]))",
               "Enum.cycle/1 is undefined or private"
             ) ==
               "Enum.flat_map(1..10, &Stream.cycle([&1]))"
    end
  end

  # ── FunctionMatcher fallback ─────────────────────────────────────

  describe "FunctionMatcher fallback — missing ? suffix" do
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

      assert fix(source, "PalindromeChecker.palindrome/1 is undefined or private", 3) ==
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

      assert fix(source, "Validator.valid/1 is undefined or private", 3) == expected
    end
  end

  describe "FunctionMatcher fallback — prefix/substring match" do
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

      assert fix(source, "Math.fib/1 is undefined or private", 3) == expected
    end
  end

  describe "FunctionMatcher fallback — no candidates" do
    test "returns source unchanged when module has no matching-arity functions" do
      source = """
      defmodule Worker do
        def process(a, b), do: a + b
        def run, do: Worker.compute(42)
      end
      """

      assert fix(source, "Worker.compute/1 is undefined or private", 3) == source
    end

    test "returns source unchanged when module not found in source" do
      source = """
      defmodule Other do
        def run, do: Missing.foo(1)
      end
      """

      assert fix(source, "Missing.foo/1 is undefined or private", 2) == source
    end
  end

  describe "FunctionMatcher fallback — known replacement takes priority" do
    test "List.drop still uses hardcoded rename, not FunctionMatcher" do
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

      assert fix(source, "List.drop/2 is undefined or private", 2) == expected
    end
  end

  describe "FunctionMatcher fallback — only considers public functions" do
    test "skips defp for module-qualified calls" do
      source = """
      defmodule Worker do
        defp helper(x), do: x * 2
        def run, do: Worker.help(42)
      end
      """

      # helper/1 is defp — excluded by visibility: :public_only
      # run/0 has wrong arity — no public arity-1 candidates
      assert fix(source, "Worker.help/1 is undefined or private", 3) == source
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "unknown function unchanged" do
      source = "MyModule.foo(x)"
      assert fix(source, "MyModule.foo/1 is undefined or private") == source
    end

    test "unknown Float function unchanged" do
      source = "Float.unknown_thing()"
      assert fix(source, "Float.unknown_thing/0 is undefined or private") == source
    end
  end
end
