defmodule Credence.Semantic.FixMultipleDefaultArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, compiles?: 1, valid_syntax?: 1]

  alias Credence.Semantic.FixMultipleDefaultArgs

  defp fix(source, message) do
    FixMultipleDefaultArgs.fix(source, %{
      severity: :error,
      message: message,
      position: {1, 1}
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

    confirm_fix(fix(input, default_msg("greet")), expected)
  end

  test "fixed output compiles" do
    input = """
    defmodule CredenceFixMultipleDefaultArgsCompileFixture do
      def greet(:hello, name \\\\ "world") do
        "Hello, \#{name}!"
      end

      def greet(:goodbye, name \\\\ "world") do
        "Goodbye, \#{name}!"
      end
    end
    """

    assert valid_syntax?(fix(input, default_msg("greet")))
    assert compiles?(fix(input, default_msg("greet")))
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

    confirm_fix(fix(input, default_msg("greet")), expected)
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

    confirm_fix(fix(input, default_msg("greet")), expected)
  end

  test "handles defp" do
    input = """
    defmodule DefpExample do
      def call, do: greet(:hello)

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
      def call, do: greet(:hello)

      defp greet(arg0, name \\\\ "world")

      defp greet(:hello, name) do
        "Hello, \#{name}!"
      end

      defp greet(:goodbye, name) do
        "Goodbye, \#{name}!"
      end
    end
    """

    confirm_fix(fix(input, "defp greet/2 defines defaults multiple times."), expected)
  end

  test "handles function names ending in a question mark" do
    input = """
    defmodule CredenceFixMultipleDefaultArgsQuestionMarkFixture do
      def enabled?(:first, fallback \\\\ false), do: fallback
      def enabled?(:second, fallback \\\\ false), do: fallback
    end
    """

    expected = """
    defmodule CredenceFixMultipleDefaultArgsQuestionMarkFixture do
      def enabled?(arg0, fallback \\\\ false)

      def enabled?(:first, fallback), do: fallback
      def enabled?(:second, fallback), do: fallback
    end
    """

    fixed = fix(input, default_msg("enabled?"))
    confirm_fix(fixed, expected)
    assert compiles?(fixed)
  end

  test "inserts the header in place, preserving imports and later defs" do
    input = """
    defmodule ImportExample do
      import String, only: [upcase: 1]

      def greet(:hello, name \\\\ "world") do
        upcase(name)
      end

      def greet(:goodbye, name \\\\ "world") do
        upcase(name)
      end

      def other, do: :ok
    end
    """

    expected = """
    defmodule ImportExample do
      import String, only: [upcase: 1]

      def greet(arg0, name \\\\ "world")

      def greet(:hello, name) do
        upcase(name)
      end

      def greet(:goodbye, name) do
        upcase(name)
      end

      def other, do: :ok
    end
    """

    fixed = fix(input, default_msg("greet"))
    confirm_fix(fixed, expected)
    assert compiles?(fixed)
  end

  test "leaves a same-name function of a different arity untouched" do
    input = """
    defmodule MixedArityExample do
      def greet(x), do: x

      def greet(:a, name \\\\ "world"), do: name

      def greet(:b, name \\\\ "world"), do: name
    end
    """

    expected = """
    defmodule MixedArityExample do
      def greet(x), do: x

      def greet(arg0, name \\\\ "world")

      def greet(:a, name), do: name

      def greet(:b, name), do: name
    end
    """

    confirm_fix(fix(input, default_msg("greet")), expected)
  end

  test "handles a structured default value" do
    input = """
    defmodule StructuredDefault do
      def walk(:pre, opts \\\\ [depth: 1, mode: :fast]) do
        opts
      end

      def walk(:post, opts \\\\ [depth: 1, mode: :fast]) do
        opts
      end
    end
    """

    expected = """
    defmodule StructuredDefault do
      def walk(arg0, opts \\\\ [depth: 1, mode: :fast])

      def walk(:pre, opts) do
        opts
      end

      def walk(:post, opts) do
        opts
      end
    end
    """

    fixed = fix(input, default_msg("walk"))
    confirm_fix(fixed, expected)
    assert compiles?(fixed)
  end

  test "no-op when clauses declare defaults on different positions" do
    input = """
    defmodule MixedPositions do
      def greet(a \\\\ 1, b) do
        a + b
      end

      def greet(a, b \\\\ 2) do
        a - b
      end
    end
    """

    confirm_fix(fix(input, default_msg("greet")), input)
  end

  test "no-op when clauses declare conflicting default values" do
    input = """
    defmodule ConflictingDefaults do
      def greet(:a, name \\\\ "world"), do: name

      def greet(:b, name \\\\ "earth"), do: name
    end
    """

    confirm_fix(fix(input, default_msg("greet")), input)
  end

  test "no-op when clauses mix def and defp" do
    input = """
    defmodule MixedKinds do
      def greet(:a, name \\\\ "world"), do: name

      defp greet(:b, name \\\\ "world"), do: name
    end
    """

    confirm_fix(fix(input, default_msg("greet")), input)
  end

  test "no-op when the message does not match the pattern" do
    input = """
    defmodule NoMatch do
      def bar(x, y \\\\ 0) do
        x + y
      end
    end
    """

    confirm_fix(fix(input, "something unrelated"), input)
  end

  test "no-op for missing @impl callback warnings (out of scope for this rule)" do
    input = """
    defmodule ImplExample do
      @behaviour Clock

      def monotonic(server, unit \\\\ :millisecond) when is_pid(server) do
        GenServer.call(server, {:monotonic, unit})
      end
    end
    """

    message =
      "module attribute @impl was not set for function monotonic/1 callback (specified in Clock). " <>
        "This either means you forgot to add the \"@impl true\" annotation before the definition " <>
        "or that you are accidentally overriding this callback"

    confirm_fix(fix(input, message), input)
  end

  test "should_report? is true exactly when the fix changes the source" do
    fixable = """
    defmodule Reportable do
      def greet(:a, name \\\\ "world"), do: name

      def greet(:b, name \\\\ "world"), do: name
    end
    """

    unfixable = """
    defmodule NotReportable do
      def greet(:a, name \\\\ "world"), do: name

      def greet(:b, name \\\\ "earth"), do: name
    end
    """

    diag = %{severity: :error, message: default_msg("greet"), position: {1, 1}}

    assert FixMultipleDefaultArgs.should_report?(diag, fixable)
    refute FixMultipleDefaultArgs.should_report?(diag, unfixable)
  end
end
