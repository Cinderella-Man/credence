defmodule Credence.Rule.NoUnnecessaryCatchAllRaiseTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoUnnecessaryCatchAllRaise.check(ast, [])
  end

  describe "NoUnnecessaryCatchAllRaise" do
    test "detects def catch-all with two-arg raise" do
      code = """
      defmodule Bad do
        def missing_number([]), do: 0

        def missing_number(nums) when is_list(nums), do: length(nums)

        def missing_number(_), do: raise(ArgumentError, "expected a list")
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_unnecessary_catch_all_raise

      assert issue.message =~ "missing_number/1"
      assert issue.message =~ "FunctionClauseError"
    end

    test "detects def catch-all with single-arg raise" do
      code = """
      defmodule Bad do
        def foo(x) when is_integer(x), do: x + 1

        def foo(_), do: raise("invalid argument")
      end
      """

      [issue] = check(code)
      assert issue.message =~ "foo/1"
    end

    test "detects defp catch-all" do
      code = """
      defmodule Bad do
        defp process([h | t]), do: {h, t}

        defp process(_), do: raise(ArgumentError, "must be a list")
      end
      """

      [issue] = check(code)
      assert issue.message =~ "defp"
      assert issue.message =~ "process/1"
    end

    test "detects catch-all with underscore-prefixed names" do
      code = """
      defmodule Bad do
        def compute(a, b) when is_number(a), do: a + b

        def compute(_a, _b), do: raise(ArgumentError, "numbers required")
      end
      """

      [issue] = check(code)
      assert issue.message =~ "compute/2"
    end

    test "detects catch-all with do...end block syntax" do
      code = """
      defmodule Bad do
        def run(cmd) when is_binary(cmd), do: cmd

        def run(_) do
          raise ArgumentError, "expected a string"
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "run/1"
    end

    test "detects catch-all raising a bare module" do
      code = """
      defmodule Bad do
        def parse(input) when is_binary(input), do: input

        def parse(_), do: raise(ArgumentError)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "parse/1"
    end

    test "detects multiple catch-alls in one module" do
      code = """
      defmodule Bad do
        def foo(_), do: raise("bad")
        def bar(_), do: raise("also bad")
      end
      """

      issues = check(code)
      assert length(issues) == 2
      names = Enum.map(issues, & &1.message)
      assert Enum.any?(names, &(&1 =~ "foo/1"))
      assert Enum.any?(names, &(&1 =~ "bar/1"))
    end

    # ---- Negative cases ----

    test "does not flag catch-all returning an error tuple" do
      code = """
      defmodule Good do
        def parse(input) when is_binary(input), do: {:ok, input}

        def parse(_), do: {:error, :invalid_input}
      end
      """

      assert check(code) == []
    end

    test "does not flag catch-all returning a default value" do
      code = """
      defmodule Good do
        def lookup(key) when is_atom(key), do: Map.get(%{}, key)

        def lookup(_), do: nil
      end
      """

      assert check(code) == []
    end

    test "does not flag clauses with non-wildcard arguments" do
      code = """
      defmodule Good do
        def foo(x), do: raise(ArgumentError, "bad \#{x}")
      end
      """

      assert check(code) == []
    end

    test "does not flag guarded wildcard clauses" do
      code = """
      defmodule Good do
        def foo(_k) when not is_integer(_k) do
          raise ArgumentError, "k must be an integer"
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag zero-arity functions that raise" do
      code = """
      defmodule Good do
        def not_implemented, do: raise("not implemented")
      end
      """

      assert check(code) == []
    end

    test "does not flag catch-all with logic before raise" do
      code = """
      defmodule Good do
        def process(_) do
          require Logger
          Logger.warning("unexpected input")
          raise ArgumentError, "bad input"
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag pattern-matched arguments even if some are wildcards" do
      code = """
      defmodule Good do
        def foo([], _), do: raise(ArgumentError, "empty list")
      end
      """

      assert check(code) == []
    end

    test "does not flag normal functions without raise" do
      code = """
      defmodule Good do
        def add(a, b), do: a + b
      end
      """

      assert check(code) == []
    end
  end
end
