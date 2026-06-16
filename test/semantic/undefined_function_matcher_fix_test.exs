defmodule Credence.Semantic.UndefinedFunction.MatcherFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction
  alias Matcher

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
  # ║  LOCAL — no FunctionMatcher fallback (too dangerous)         ║
  # ╚═══════════════════════════════════════════════════════════════╝

  describe "local: no FunctionMatcher fallback" do
    test "does NOT replace list_to_tuple with enclosing function (recursion bug)" do
      source = """
      defmodule Solution do
        def findmaxinrotatedlist(list) do
          tuple = list_to_tuple(list)
          do_find_max(tuple, 0, tuple_size(tuple) - 1)
        end

        defp do_find_max(tuple, low, high) when low == high, do: elem(tuple, low)
        defp do_find_max(tuple, low, high), do: do_find_max(tuple, low + 1, high)
      end
      """

      # Must NOT rewrite list_to_tuple → findmaxinrotatedlist (infinite recursion)
      assert fix_local(source, "undefined function list_to_tuple/1", 3) == source
    end

    test "unknown local function with module hint is left unchanged" do
      source = """
      defmodule Calculator do
        def compute(n), do: n * 2
        def run(n), do: calculate(n)
      end
      """

      assert fix_local(
               source,
               "undefined function calculate/1 (expected Calculator to define such a function or for it to be imported, but none are available)",
               3
             ) == source
    end

    test "module name not in error message" do
      source = "fibonacci(5)"

      assert fix_local(source, "undefined function fibonacci/1", 1) == source
    end
  end
end
