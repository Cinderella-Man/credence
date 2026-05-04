defmodule Credence.Rule.NoUnderscoreFunctionNameTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoUnderscoreFunctionName.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoUnderscoreFunctionName.fix(code, [])
  end

  describe "NoUnderscoreFunctionName — check" do
    test "detects defp with underscore prefix" do
      code = """
      defmodule Bad do
        def factorial(n), do: _factorial(n, 1)
        defp _factorial(0, acc), do: acc
        defp _factorial(n, acc), do: _factorial(n - 1, n * acc)
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert Enum.all?(issues, &(&1.rule == :no_underscore_function_name))
      assert Enum.all?(issues, &(&1.message =~ "_factorial"))
      assert Enum.all?(issues, &(&1.message =~ "do_factorial"))
    end

    test "detects def with underscore prefix" do
      code = """
      defmodule Bad do
        def _helper(x), do: x + 1
      end
      """

      [issue] = check(code)
      assert issue.message =~ "def _helper/1"
    end

    test "detects guarded function with underscore prefix" do
      code = """
      defmodule Bad do
        defp _fibonacci(count, acc, next) when count > 0 do
          _fibonacci(count - 1, next, acc + next)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "_fibonacci"
      assert issue.message =~ "do_fibonacci"
    end

    test "detects underscore prefix with multiple underscores in name" do
      code = """
      defmodule Bad do
        defp _do_largest_cont_sum([], _, max_sum), do: max_sum
      end
      """

      [issue] = check(code)
      assert issue.message =~ "_do_largest_cont_sum"
    end

    test "detects multiple different underscore functions" do
      code = """
      defmodule Bad do
        defp _foo(x), do: x
        defp _bar(y), do: y
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "does not flag do_ prefix (idiomatic)" do
      code = """
      defmodule Good do
        defp do_factorial(0, acc), do: acc
        defp do_factorial(n, acc), do: do_factorial(n - 1, n * acc)
      end
      """

      assert check(code) == []
    end

    test "does not flag regular function names" do
      code = """
      defmodule Good do
        def factorial(n), do: n
        defp compute(x), do: x * 2
      end
      """

      assert check(code) == []
    end

    test "does not flag names with underscores in the middle" do
      code = """
      defmodule Good do
        def is_valid_ipv4(ip), do: true
        defp find_cycle_swaps(idx, map, visited), do: {0, visited}
      end
      """

      assert check(code) == []
    end

    test "does not flag dunder names (__using__, __before_compile__)" do
      code = """
      defmodule Good do
        defmacro __using__(opts) do
          quote do: nil
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag zero-arity functions" do
      code = """
      defmodule Good do
        def start, do: :ok
        defp init, do: %{}
      end
      """

      assert check(code) == []
    end
  end

  describe "NoUnderscoreFunctionName — fix" do
    test "renames recursive function and all call sites" do
      input = """
      defmodule Example do
        def factorial(n), do: _factorial(n, 1)

        defp _factorial(0, acc), do: acc
        defp _factorial(n, acc), do: _factorial(n - 1, n * acc)
      end
      """

      output = fix(input)
      assert output =~ "defp do_factorial(0, acc), do: acc"
      assert output =~ "do_factorial(n - 1, n * acc)"
      assert output =~ "_factorial(n, 1)"
      refute output =~ "defp _factorial"
    end

    test "renames single-clause keyword syntax" do
      input = """
      defmodule Example do
        defp _helper(x), do: x + 1
      end
      """

      output = fix(input)
      assert output =~ "defp do_helper(x), do: x + 1"
      refute output =~ ~r/(?<!do)_helper/
    end

    test "renames guarded function with recursive call" do
      input = """
      defmodule Example do
        defp _fibonacci(count, acc, next) when count > 0 do
          _fibonacci(count - 1, next, acc + next)
        end
      end
      """

      output = fix(input)
      assert output =~ "defp do_fibonacci(count, acc, next) when count > 0 do"
      assert output =~ "do_fibonacci(count - 1, next, acc + next)"
      refute output =~ ~r/(?<!do)_fibonacci/
    end

    test "renames function with multi-line body" do
      input = """
      defmodule Example do
        defp _process(list) do
          Enum.reduce(list, {0, []}, fn x, {sum, acc} ->
            _process(x)
            {sum + x, [x | acc]}
          end)
        end
      end
      """

      output = fix(input)
      assert output =~ "defp do_process(list) do"
      assert output =~ "do_process(x)"
      refute output =~ ~r/(?<!do)_process/
    end

    test "renames multiple underscore functions" do
      input = """
      defmodule Example do
        defp _foo(x), do: _bar(x + 1)
        defp _bar(y), do: y * 2
      end
      """

      output = fix(input)
      assert output =~ "defp do_foo(x), do: do_bar(x + 1)"
      assert output =~ "defp do_bar(y), do: y * 2"
      refute output =~ ~r/(?<!do)_foo/
      refute output =~ ~r/(?<!do)_bar/
    end

    test "does not modify idiomatic do_ prefix" do
      input = """
      defmodule Good do
        defp do_factorial(0, acc), do: acc
        defp do_factorial(n, acc), do: do_factorial(n - 1, n * acc)
      end
      """

      assert fix(input) == input
    end

    test "does not modify dunder names" do
      input = """
      defmodule Good do
        defmacro __using__(opts) do
          quote do: nil
        end
      end
      """

      assert fix(input) == input
    end

    test "returns source unchanged when no underscore functions present" do
      input = """
      defmodule Good do
        def factorial(n), do: n
        defp compute(x), do: x * 2
      end
      """

      assert fix(input) == input
    end

    test "roundtrip: fixed code produces no issues" do
      code = """
      defmodule Example do
        def factorial(n), do: _factorial(n, 1)

        defp _factorial(0, acc), do: acc
        defp _factorial(n, acc), do: _factorial(n - 1, n * acc)
      end
      """

      fixed = fix(code)
      {:ok, fixed_ast} = Code.string_to_quoted(fixed)
      assert Credence.Rule.NoUnderscoreFunctionName.check(fixed_ast, []) == []
    end
  end
end
