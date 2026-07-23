defmodule Credence.Semantic.NoConflictingDefaultArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoConflictingDefaultArgs

  defp fix(source, message, line) do
    NoConflictingDefaultArgs.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  defp conflict_msg(fun, low_arity, high_arity) do
    "def #{fun}/#{low_arity} conflicts with defaults from #{fun}/#{high_arity}"
  end

  test "removes redundant lower-arity clause with when guard" do
    input = """
    defmodule Example do
      def sequence(name, formatter_fn \\\\ fn n -> n end) do
        {name, formatter_fn}
      end

      def sequence(name) when is_atom(name) do
        sequence(name, fn n -> n end)
      end
    end
    """

    expected = """
    defmodule Example do
      def sequence(name, formatter_fn \\\\ fn n -> n end) do
        {name, formatter_fn}
      end
    end
    """

    confirm_fix(fix(input, conflict_msg("sequence", 1, 2), 6), expected)
  end

  test "removes redundant lower-arity clause without guard" do
    input = """
    defmodule Example2 do
      def greet(name, greeting \\\\ "Hello") do
        "\#{greeting}, \#{name}!"
      end

      def greet(name) do
        greet(name, "Hello")
      end
    end
    """

    expected = """
    defmodule Example2 do
      def greet(name, greeting \\\\ "Hello") do
        "\#{greeting}, \#{name}!"
      end
    end
    """

    confirm_fix(fix(input, conflict_msg("greet", 1, 2), 6), expected)
  end

  test "fixed output is well-formed and drops only the conflicting clause" do
    input = """
    defmodule ParseCheck do
      def foo(a, b \\\\ :ok) do
        {a, b}
      end

      def foo(a) do
        foo(a, :ok)
      end
    end
    """

    expected = """
    defmodule ParseCheck do
      def foo(a, b \\\\ :ok) do
        {a, b}
      end
    end
    """

    assert valid_syntax?(fix(input, conflict_msg("foo", 1, 2), 6))
    confirm_fix(fix(input, conflict_msg("foo", 1, 2), 6), expected)
  end

  test "returns source unchanged when clause not found at position" do
    input = """
    defmodule NoMatch do
      def bar(x, y \\\\ 0) do
        x + y
      end
    end
    """

    result = fix(input, conflict_msg("bar", 1, 2), 99)
    confirm_fix(result, input)
  end

  test "returns source unchanged when message does not match pattern" do
    input = """
    defmodule NoParse do
      def baz, do: :ok
    end
    """

    result = fix(input, "something unrelated", 2)
    confirm_fix(result, input)
  end
end
