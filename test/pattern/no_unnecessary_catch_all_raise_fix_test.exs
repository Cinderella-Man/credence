defmodule Credence.Pattern.NoUnnecessaryCatchAllRaiseFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUnnecessaryCatchAllRaise

  describe "fix/2" do
    test "removes simple keyword-style catch-all raise" do
      input = """
      defmodule Bad do
        def missing_number([]), do: 0
        def missing_number(nums) when is_list(nums), do: length(nums)
        def missing_number(_), do: raise(ArgumentError, "expected a list")
      end
      """

      expected = """
      defmodule Bad do
        def missing_number([]), do: 0
        def missing_number(nums) when is_list(nums), do: length(nums)
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
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

      expected = """
      defmodule Bad do
        def run(cmd) when is_binary(cmd), do: cmd
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
    end

    test "removes multiple catch-all clauses" do
      input = """
      defmodule Bad do
        def foo(_), do: raise("bad")
        def bar(_), do: raise("also bad")
      end
      """

      expected = """
      defmodule Bad do
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
    end

    test "removes defp catch-all" do
      input = """
      defmodule Bad do
        defp process([h | t]), do: {h, t}
        defp process(_), do: raise(ArgumentError, "must be a list")
      end
      """

      expected = """
      defmodule Bad do
        defp process([h | t]), do: {h, t}
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
    end

    test "removes catch-all with underscore-prefixed names" do
      input = """
      defmodule Bad do
        def compute(a, b) when is_number(a), do: a + b
        def compute(_a, _b), do: raise(ArgumentError, "numbers required")
      end
      """

      expected = """
      defmodule Bad do
        def compute(a, b) when is_number(a), do: a + b
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
    end

    test "removes catch-all raising a bare module" do
      input = """
      defmodule Bad do
        def parse(input) when is_binary(input), do: input
        def parse(_), do: raise(ArgumentError)
      end
      """

      expected = """
      defmodule Bad do
        def parse(input) when is_binary(input), do: input
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
    end

    test "removes catch-all that is only function in module" do
      input = """
      defmodule Bad do
        def validate(_), do: raise("always raises")
      end
      """

      expected = """
      defmodule Bad do
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
    end

    test "removes catch-all do-block that is only function in module" do
      input = """
      defmodule Bad do
        def validate(_) do
          raise "always raises"
        end
      end
      """

      expected = """
      defmodule Bad do
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
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

      expected = """
      defmodule Bad do
        def parse(input) when is_binary(input), do: input
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
    end

    test "preserves non-catch-all clauses when removing others" do
      input = """
      defmodule Mixed do
        def valid(input) when is_binary(input), do: {:ok, input}
        def valid(_), do: {:error, :invalid}
        def bad(_), do: raise("should not happen")
      end
      """

      expected = """
      defmodule Mixed do
        def valid(input) when is_binary(input), do: {:ok, input}
        def valid(_), do: {:error, :invalid}
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, input) == expected
    end

    test "no-op when no catch-all raises present" do
      code = """
      defmodule Good do
        def parse(input) when is_binary(input), do: {:ok, input}
        def parse(_), do: {:error, :invalid_input}
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, code) == code
    end

    test "no-op for guarded wildcard clauses" do
      code = """
      defmodule Good do
        def foo(_k) when not is_integer(_k) do
          raise ArgumentError, "k must be an integer"
        end
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, code) == code
    end

    test "no-op for zero-arity functions that raise" do
      code = """
      defmodule Good do
        def not_implemented, do: raise("not implemented")
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, code) == code
    end

    test "no-op for catch-all with logic before raise" do
      code = """
      defmodule Good do
        def process(_) do
          require Logger
          Logger.warning("unexpected input")
          raise ArgumentError, "bad input"
        end
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, code) == code
    end

    test "no-op for catch-all returning error tuple" do
      code = """
      defmodule Good do
        def parse(input) when is_binary(input), do: {:ok, input}
        def parse(_), do: {:error, :invalid_input}
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, code) == code
    end

    test "no-op for pattern-matched arguments with some wildcards" do
      code = """
      defmodule Good do
        def foo([], _), do: raise(ArgumentError, "empty list")
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, code) == code
    end

    test "no-op for normal functions without raise" do
      code = """
      defmodule Good do
        def add(a, b), do: a + b
      end
      """

      assert fix(NoUnnecessaryCatchAllRaise, code) == code
    end
  end
end
