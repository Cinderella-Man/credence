defmodule Credence.Semantic.NoDefpAlreadyDefinedAsDefFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDefpAlreadyDefinedAsDef

  @real_message "defp sequence/2 already defined as def"

  defp fix(source, message, line \\ 1) do
    NoDefpAlreadyDefinedAsDef.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "renames defp to do_<name> when argument patterns differ from def" do
    input = """
    defmodule M do
      use GenServer

      def stab_count(server, point) do
        GenServer.call(server, {:stab_count, point})
      end

      def init(state), do: {:ok, state}

      def handle_call({:stab_count, point}, _from, tree) do
        {:reply, stab_count(tree, point), tree}
      end

      defp stab_count(nil, _point), do: 0
      defp stab_count(%{left: l, right: r}, point) do
        1 + stab_count(l, point) + stab_count(r, point)
      end
    end
    """

    expected = """
    defmodule M do
      use GenServer

      def stab_count(server, point) do
        GenServer.call(server, {:stab_count, point})
      end

      def init(state), do: {:ok, state}

      def handle_call({:stab_count, point}, _from, tree) do
        {:reply, do_stab_count(tree, point), tree}
      end

      defp do_stab_count(nil, _point), do: 0

      defp do_stab_count(%{left: l, right: r}, point) do
        1 + do_stab_count(l, point) + do_stab_count(r, point)
      end
    end
    """

    confirm_fix(fix(input, "defp stab_count/2 already defined as def", 15), expected)
  end

  test "renames defp when its body differs from the public clause" do
    input = """
    defmodule Example do
      def greet(name) do
        "Hello, " <> name
      end

      defp greet(name) do
        "Hi, " <> name
      end
    end
    """

    expected = """
    defmodule Example do
      def greet(name) do
        "Hello, " <> name
      end

      defp do_greet(name) do
        "Hi, " <> name
      end
    end
    """

    confirm_fix(fix(input, "defp greet/1 already defined as def", 6), expected)
  end

  test "renames defp when its guard and body differ from the public clause" do
    input = """
    defmodule Example do
      def sequence(name, formatter_fn) do
        formatter_fn.(name)
      end

      # ... other code ...

      defp sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
        formatter_fn.(name + 1)
      end
    end
    """

    expected = """
    defmodule Example do
      def sequence(name, formatter_fn) do
        formatter_fn.(name)
      end

      # ... other code ...

      defp do_sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
        formatter_fn.(name + 1)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 8), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def greet(name) do
        "Hello, " <> name
      end

      defp greet(name) do
        "Hi, " <> name
      end
    end
    """

    assert valid_syntax?(fix(input, "defp greet/1 already defined as def", 6))
  end

  test "removes a genuinely identical private clause" do
    input = """
    defmodule IdenticalClauseFixture do
      def greet(name), do: "Hello, " <> name
      defp greet(name), do: "Hello, " <> name
    end
    """

    expected = """
    defmodule IdenticalClauseFixture do
      def greet(name), do: "Hello, " <> name
    end
    """

    confirm_fix(fix(input, "defp greet/1 already defined as def", 3), expected)
  end

  test "returns source unchanged when no matching defp found" do
    input = """
    defmodule Example do
      def other(name) do
        name
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule Example do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "renames only private clauses with the diagnostic arity" do
    input = """
    defmodule ArityFixture do
      def foo(x), do: x
      defp foo(0), do: foo(1)
      defp foo(x, y), do: foo(x, y - 1)
    end
    """

    expected = """
    defmodule ArityFixture do
      def foo(x), do: x
      defp do_foo(0), do: do_foo(1)
      defp foo(x, y), do: foo(x, y - 1)
    end
    """

    confirm_fix(fix(input, "defp foo/1 already defined as def", 3), expected)
  end

  test "limits call rewriting to the diagnostic module and preserves public recursion" do
    input = """
    defmodule ScopeFixtureA do
      def foo(x), do: foo(x - 1)
      def run(x), do: foo(x)
      defp foo(0), do: 0
    end

    defmodule ScopeFixtureB do
      def run(x), do: foo(x)
    end
    """

    expected = """
    defmodule ScopeFixtureA do
      def foo(x), do: foo(x - 1)
      def run(x), do: do_foo(x)
      defp do_foo(0), do: 0
    end

    defmodule ScopeFixtureB do
      def run(x), do: foo(x)
    end
    """

    confirm_fix(fix(input, "defp foo/1 already defined as def", 4), expected)
  end

  test "stale diagnostic does not rewrite calls without a matching private definition" do
    input = """
    defmodule StaleDiagnosticFixture do
      def foo(x), do: x
      def run(x), do: foo(x)
    end
    """

    confirm_fix(fix(input, "defp foo/1 already defined as def", 2), input)
  end

  test "dispatches a compiler diagnostic through the semantic pipeline" do
    input = """
    defmodule NoDefpPipelineFixture do
      def foo(x), do: x
      defp foo(0), do: 0
    end
    """

    expected = """
    defmodule NoDefpPipelineFixture do
      def foo(x), do: x
      defp do_foo(0), do: 0
    end
    """

    {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)

    assert Enum.any?(diagnostics, &NoDefpAlreadyDefinedAsDef.match?/1)
    fixed = Credence.Semantic.fix(input)
    confirm_fix(fixed, expected)
    assert {:ok, fixed_diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed)
    refute Enum.any?(fixed_diagnostics, &(&1.severity == :error))
    assert {:ok, expected_diagnostics} = Credence.RuleHelpers.compile_and_capture(expected)
    refute Enum.any?(expected_diagnostics, &(&1.severity == :error))
  end
end
