defmodule Credence.Semantic.NoConflictingDefaultArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
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

  test "preserves a lower-arity clause with a when guard" do
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

    confirm_fix(fix(input, conflict_msg("sequence", 1, 2), 6), input)
  end

  test "real compiler diagnostic is repaired through the semantic pipeline" do
    input = """
    defmodule PipelineDefaultArgs do
      def greet(name, greeting \\\\ "Hello"), do: {greeting, name}
      def greet(name), do: greet(name, "Hello")
    end
    """

    expected = """
    defmodule PipelineDefaultArgs do
      def greet(name, greeting \\\\ "Hello"), do: {greeting, name}
    end
    """

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)

    assert Enum.any?(diagnostics, fn diagnostic ->
             NoConflictingDefaultArgs.match?(diagnostic) and diagnostic.position == {3, 7}
           end)

    confirm_fix(Credence.Semantic.fix(input), expected)
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

  test "does not delete a lower-arity clause with different behavior" do
    input = """
    defmodule ConflictingBehavior do
      def foo(x, y \\\\ 0), do: {:default, x, y}
      def foo(x), do: {:special, x}
    end
    """

    emitted = fix(input, conflict_msg("foo", 1, 2), 3)

    confirm_fix(emitted, input)
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(input)
  end

  test "removes an equivalent clause when the module has a top-level sibling" do
    input = """
    :top_level

    defmodule TopLevelSibling do
      def foo(x, y \\\\ 0), do: {x, y}
      def foo(x), do: foo(x, 0)
    end
    """

    expected = """
    :top_level

    defmodule TopLevelSibling do
      def foo(x, y \\\\ 0), do: {x, y}
    end
    """

    emitted = fix(input, conflict_msg("foo", 1, 2), 5)

    confirm_fix(emitted, expected)
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(expected)
  end

  test "removes an equivalent clause from a nested module" do
    input = """
    defmodule OuterDefaultArgs do
      defmodule InnerDefaultArgs do
        def foo(x, y \\\\ 0), do: {x, y}
        def foo(x), do: foo(x, 0)
      end
    end
    """

    expected = """
    defmodule OuterDefaultArgs do
      defmodule InnerDefaultArgs do
        def foo(x, y \\\\ 0), do: {x, y}
      end
    end
    """

    emitted = fix(input, conflict_msg("foo", 1, 2), 4)

    confirm_fix(emitted, expected)
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(expected)
  end
end
