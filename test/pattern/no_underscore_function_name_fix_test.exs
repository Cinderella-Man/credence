defmodule Credence.Pattern.NoUnderscoreFunctionNameFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUnderscoreFunctionName

  describe "NoUnderscoreFunctionName — fix" do
    test "renames recursive function and all call sites" do
      input = """
      defmodule Example do
        def factorial(n), do: _factorial(n, 1)

        defp _factorial(0, acc), do: acc
        defp _factorial(n, acc), do: _factorial(n - 1, n * acc)
      end
      """

      expected = """
      defmodule Example do
        def factorial(n), do: do_factorial(n, 1)

        defp do_factorial(0, acc), do: acc
        defp do_factorial(n, acc), do: do_factorial(n - 1, n * acc)
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), expected)
    end

    test "renames single-clause keyword syntax" do
      input = """
      defmodule Example do
        defp _helper(x), do: x + 1
      end
      """

      expected = """
      defmodule Example do
        defp do_helper(x), do: x + 1
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), expected)
    end

    test "renames guarded function with recursive call" do
      input = """
      defmodule Example do
        defp _fibonacci(count, acc, next) when count > 0 do
          _fibonacci(count - 1, next, acc + next)
        end
      end
      """

      expected = """
      defmodule Example do
        defp do_fibonacci(count, acc, next) when count > 0 do
          do_fibonacci(count - 1, next, acc + next)
        end
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), expected)
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

      expected = """
      defmodule Example do
        defp do_process(list) do
          Enum.reduce(list, {0, []}, fn x, {sum, acc} ->
            do_process(x)
            {sum + x, [x | acc]}
          end)
        end
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), expected)
    end

    test "renames multiple underscore functions" do
      input = """
      defmodule Example do
        defp _foo(x), do: _bar(x + 1)
        defp _bar(y), do: y * 2
      end
      """

      expected = """
      defmodule Example do
        defp do_foo(x), do: do_bar(x + 1)
        defp do_bar(y), do: y * 2
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), expected)
    end

    test "does not modify idiomatic do_ prefix" do
      input = """
      defmodule Good do
        defp do_factorial(0, acc), do: acc
        defp do_factorial(n, acc), do: do_factorial(n - 1, n * acc)
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), input)
    end

    test "does not modify dunder names" do
      input = """
      defmodule Good do
        defmacro __using__(opts) do
          quote do: nil
        end
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), input)
    end

    test "returns source unchanged when no underscore functions present" do
      input = """
      defmodule Good do
        def factorial(n), do: n
        defp compute(x), do: x * 2
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), input)
    end

    test "roundtrip: fixed code produces no issues" do
      code = """
      defmodule Example do
        def factorial(n), do: _factorial(n, 1)

        defp _factorial(0, acc), do: acc
        defp _factorial(n, acc), do: _factorial(n - 1, n * acc)
      end
      """

      assert check(NoUnderscoreFunctionName, fix(NoUnderscoreFunctionName, code)) == []
    end

    # An arity-style capture `&_name/arity` cannot be rewritten by the rename
    # (its node looks like a bare variable), so renaming the def would strand
    # the capture pointing at a now-missing name. The fix must leave the whole
    # function alone rather than ship code that fails to compile.
    test "leaves a function referenced by &_name/arity untouched" do
      input = """
      defmodule Example do
        def run(list), do: Enum.map(list, &_step/1)

        defp _step(x), do: x + 1
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), input)
    end

    test "renames a call-style capture &_name(&1) along with the def" do
      input = """
      defmodule Example do
        def run(list), do: Enum.map(list, &_step(&1))

        defp _step(x), do: x + 1
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.map(list, &do_step(&1))

        defp do_step(x), do: x + 1
      end
      """

      confirm_fix(fix(NoUnderscoreFunctionName, input), expected)
    end
  end
end
