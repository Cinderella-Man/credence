defmodule Credence.Pattern.NoUnnecessaryCatchAllRaiseTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoUnnecessaryCatchAllRaise.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoUnnecessaryCatchAllRaise.fix(code, [])
  end

  defp normalize(str), do: String.trim_trailing(str, "\n")

  describe "NoUnnecessaryCatchAllRaise" do
    # --- POSITIVE CASES (should flag) ---

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

  describe "fix/2" do
    test "removes simple keyword-style catch-all raise" do
      input = """
      defmodule Bad do
        def missing_number([]), do: 0
        def missing_number(nums) when is_list(nums), do: length(nums)
        def missing_number(_), do: raise(ArgumentError, "expected a list")
      end
      """

      result = fix(input)
      assert result =~ "def missing_number([]), do: 0"
      assert result =~ "def missing_number(nums) when is_list(nums), do: length(nums)"
      refute result =~ "raise"
    end

    test "removes catch-all with do...end block" do
      input = """
      defmodule Bad do
        def run(cmd) when is_binary(cmd), do: cmd
        def run(_) do
          raise ArgumentError, "expected a string"
        end
      end
      """

      result = fix(input)
      assert result =~ "def run(cmd) when is_binary(cmd), do: cmd"
      refute result =~ "raise"
    end

    test "removes multiple catch-all clauses" do
      input = """
      defmodule Bad do
        def foo(_), do: raise("bad")
        def bar(_), do: raise("also bad")
      end
      """

      result = fix(input)
      assert result =~ "defmodule Bad do"
      assert result =~ "end"
      refute result =~ "raise"
    end

    test "removes defp catch-all" do
      input = """
      defmodule Bad do
        defp process([h | t]), do: {h, t}
        defp process(_), do: raise(ArgumentError, "must be a list")
      end
      """

      result = fix(input)
      assert result =~ "defp process([h | t]), do: {h, t}"
      refute result =~ "raise"
    end

    test "removes catch-all with underscore-prefixed names" do
      input = """
      defmodule Bad do
        def compute(a, b) when is_number(a), do: a + b
        def compute(_a, _b), do: raise(ArgumentError, "numbers required")
      end
      """

      result = fix(input)
      assert result =~ "def compute(a, b) when is_number(a), do: a + b"
      refute result =~ "raise"
    end

    test "removes catch-all raising a bare module" do
      input = """
      defmodule Bad do
        def parse(input) when is_binary(input), do: input
        def parse(_), do: raise(ArgumentError)
      end
      """

      result = fix(input)
      assert result =~ "def parse(input) when is_binary(input), do: input"
      refute result =~ "raise"
    end

    test "removes catch-all that is only function in module" do
      input = """
      defmodule Bad do
        def validate(_), do: raise("always raises")
      end
      """

      result = fix(input)
      assert result =~ "defmodule Bad do"
      assert result =~ "end"
      refute result =~ "raise"
      refute result =~ "validate"
    end

    test "removes catch-all do-block that is only function in module" do
      input = """
      defmodule Bad do
        def validate(_) do
          raise "always raises"
        end
      end
      """

      result = fix(input)
      assert result =~ "defmodule Bad do"
      assert result =~ "end"
      refute result =~ "raise"
      refute result =~ "validate"
    end

    test "removes catch-all with single-arg raise (no message)" do
      input = """
      defmodule Bad do
        def parse(input) when is_binary(input), do: input
        def parse(_) do
          raise ArgumentError
        end
      end
      """

      result = fix(input)
      assert result =~ "def parse(input) when is_binary(input), do: input"
      refute result =~ "raise"
    end

    test "preserves non-catch-all clauses when removing others" do
      input = """
      defmodule Mixed do
        def valid(input) when is_binary(input), do: {:ok, input}
        def valid(_), do: {:error, :invalid}
        def bad(_), do: raise("should not happen")
      end
      """

      result = fix(input)
      assert result =~ "def valid(input) when is_binary(input), do: {:ok, input}"
      assert result =~ "def valid(_), do: {:error, :invalid}"
      refute result =~ "bad(_)"
    end

    test "no-op when no catch-all raises present" do
      input = """
      defmodule Good do
        def parse(input) when is_binary(input), do: {:ok, input}
        def parse(_), do: {:error, :invalid_input}
      end
      """

      assert normalize(fix(input)) == normalize(input)
    end

    test "no-op for guarded wildcard clauses" do
      input = """
      defmodule Good do
        def foo(_k) when not is_integer(_k) do
          raise ArgumentError, "k must be an integer"
        end
      end
      """

      assert normalize(fix(input)) == normalize(input)
    end

    test "no-op for zero-arity functions that raise" do
      input = """
      defmodule Good do
        def not_implemented, do: raise("not implemented")
      end
      """

      assert normalize(fix(input)) == normalize(input)
    end

    test "no-op for catch-all with logic before raise" do
      input = """
      defmodule Good do
        def process(_) do
          require Logger
          Logger.warning("unexpected input")
          raise ArgumentError, "bad input"
        end
      end
      """

      assert normalize(fix(input)) == normalize(input)
    end

    test "no-op for catch-all returning error tuple" do
      input = """
      defmodule Good do
        def parse(input) when is_binary(input), do: {:ok, input}
        def parse(_), do: {:error, :invalid_input}
      end
      """

      assert normalize(fix(input)) == normalize(input)
    end

    test "no-op for pattern-matched arguments with some wildcards" do
      input = """
      defmodule Good do
        def foo([], _), do: raise(ArgumentError, "empty list")
      end
      """

      assert normalize(fix(input)) == normalize(input)
    end

    test "no-op for normal functions without raise" do
      input = """
      defmodule Good do
        def add(a, b), do: a + b
      end
      """

      assert normalize(fix(input)) == normalize(input)
    end
  end
end
