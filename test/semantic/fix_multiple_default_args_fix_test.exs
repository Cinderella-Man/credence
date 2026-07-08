defmodule Credence.Semantic.FixMultipleDefaultArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixMultipleDefaultArgs

  defp fix(source, message, line \\ 1) do
    FixMultipleDefaultArgs.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  defp default_msg(fun, arity \\ 2) do
    "def #{fun}/#{arity} defines defaults multiple times."
  end

  test "extracts a header clause and removes defaults from pattern clauses" do
    input = """
    defmodule Example do
      def greet(:hello, name \\\\ "world") do
        "Hello, \#{name}!"
      end

      def greet(:goodbye, name \\\\ "world") do
        "Goodbye, \#{name}!"
      end
    end
    """

    expected = """
    defmodule Example do
      def greet(arg0, name \\\\ "world")

      def greet(:hello, name) do
        "Hello, \#{name}!"
      end

      def greet(:goodbye, name) do
        "Goodbye, \#{name}!"
      end
    end
    """

    confirm_fix(fix(input, default_msg("greet"), 6), expected)
  end

  test "preserves guards on pattern clauses" do
    input = """
    defmodule GuardedExample do
      def greet(:hello, name \\\\ "world") when is_binary(name) do
        "Hello, \#{name}!"
      end

      def greet(:goodbye, name \\\\ "world") do
        "Goodbye, \#{name}!"
      end
    end
    """

    expected = """
    defmodule GuardedExample do
      def greet(arg0, name \\\\ "world")

      def greet(:hello, name) when is_binary(name) do
        "Hello, \#{name}!"
      end

      def greet(:goodbye, name) do
        "Goodbye, \#{name}!"
      end
    end
    """

    confirm_fix(fix(input, default_msg("greet"), 6), expected)
  end

  test "handles three clauses" do
    input = """
    defmodule ThreeClauses do
      def greet(:hello, name \\\\ "world") do
        "Hello, \#{name}!"
      end

      def greet(:goodbye, name \\\\ "world") do
        "Goodbye, \#{name}!"
      end

      def greet(:thanks, name \\\\ "world") do
        "Thanks, \#{name}!"
      end
    end
    """

    expected = """
    defmodule ThreeClauses do
      def greet(arg0, name \\\\ "world")

      def greet(:hello, name) do
        "Hello, \#{name}!"
      end

      def greet(:goodbye, name) do
        "Goodbye, \#{name}!"
      end

      def greet(:thanks, name) do
        "Thanks, \#{name}!"
      end
    end
    """

    confirm_fix(fix(input, default_msg("greet"), 10), expected)
  end

  test "handles defp" do
    input = """
    defmodule DefpExample do
      defp greet(:hello, name \\\\ "world") do
        "Hello, \#{name}!"
      end

      defp greet(:goodbye, name \\\\ "world") do
        "Goodbye, \#{name}!"
      end
    end
    """

    expected = """
    defmodule DefpExample do
      defp greet(arg0, name \\\\ "world")

      defp greet(:hello, name) do
        "Hello, \#{name}!"
      end

      defp greet(:goodbye, name) do
        "Goodbye, \#{name}!"
      end
    end
    """

    confirm_fix(fix(input, "defp greet/2 defines defaults multiple times.", 6), expected)
  end

  test "returns source unchanged when message does not match pattern" do
    input = """
    defmodule NoMatch do
      def bar(x, y \\\\ 0) do
        x + y
      end
    end
    """

    result = fix(input, "something unrelated", 2)
    confirm_fix(result, input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ParseCheck do
      def foo(:a, x \\\\ 1) do
        x
      end

      def foo(:b, x \\\\ 1) do
        x
      end
    end
    """

    assert valid_syntax?(fix(input, default_msg("foo"), 6))
  end
end
