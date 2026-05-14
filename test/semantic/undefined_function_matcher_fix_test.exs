defmodule Credence.Semantic.UndefinedFunction.MatcherFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp fix_qualified(source, message, line) do
    UndefinedFunction.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  defp fix_local(source, message, line) do
    UndefinedFunction.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  # ╔═══════════════════════════════════════════════════════════════╗
  # ║  QUALIFIED — FunctionMatcher fallback                        ║
  # ╚═══════════════════════════════════════════════════════════════╝

  describe "qualified: FunctionMatcher — missing ? suffix" do
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

  describe "qualified: FunctionMatcher — prefix match" do
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

  describe "qualified: FunctionMatcher — no candidates" do
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

  describe "qualified: FunctionMatcher — priority" do
    test "known replacement takes priority" do
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

  describe "qualified: FunctionMatcher — visibility" do
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

  # ╔═══════════════════════════════════════════════════════════════╗
  # ║  LOCAL — FunctionMatcher fallback                            ║
  # ╚═══════════════════════════════════════════════════════════════╝

  describe "local: FunctionMatcher — missing ? suffix" do
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

  describe "local: FunctionMatcher — __ demangle" do
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

  describe "local: FunctionMatcher — prefix/substring" do
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

  describe "local: FunctionMatcher — sole candidate" do
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

  describe "local: FunctionMatcher — no candidates" do
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

  describe "local: FunctionMatcher — includes defp" do
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

  describe "local: FunctionMatcher — priority" do
    test "known replacement takes priority" do
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

      assert fix_local(
               source,
               "undefined function max/1 (expected MyModule to define such a function or for it to be imported, but none are available)",
               3
             ) == expected
    end
  end
end
