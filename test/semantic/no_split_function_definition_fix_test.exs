defmodule Credence.Semantic.NoSplitFunctionDefinitionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoSplitFunctionDefinition

  defp fix(source, message, line \\ 1) do
    NoSplitFunctionDefinition.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  @split_msg "function handle_call/3 has multiple clauses and they are not adjacent"

  test "fixes split function definitions" do
    input = """
    defmodule SplitDefs do
      def start_link(opts), do: :ok

      def handle_call({:get, key}, _from, state) do
        {:reply, Map.get(state, key), state}
      end

      def helper(), do: :ok

      def handle_call({:put, key, value}, _from, state) do
        {:reply, :ok, Map.put(state, key, value)}
      end

      def init(opts), do: {:ok, %{}}
    end
    """

    expected = """
    defmodule SplitDefs do
      def start_link(opts), do: :ok

      def handle_call({:get, key}, _from, state) do
        {:reply, Map.get(state, key), state}
      end

      def handle_call({:put, key, value}, _from, state) do
        {:reply, :ok, Map.put(state, key, value)}
      end

      def helper(), do: :ok

      def init(opts), do: {:ok, %{}}
    end
    """

    confirm_fix(fix(input, @split_msg), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def foo(1), do: :a
      def bar(), do: :ok
      def foo(2), do: :b
    end
    """

    assert valid_syntax?(fix(input, "function foo/1 has multiple clauses and they are not adjacent"))
  end

  test "groups three split clauses" do
    input = """
    defmodule ThreeWay do
      def foo(1), do: :a
      def bar(), do: :ok
      def foo(2), do: :b
      def baz(), do: :ok
      def foo(3), do: :c
    end
    """

    expected = """
    defmodule ThreeWay do
      def foo(1), do: :a
      def foo(2), do: :b
      def foo(3), do: :c
      def bar(), do: :ok
      def baz(), do: :ok
    end
    """

    confirm_fix(fix(input, "function foo/1 has multiple clauses and they are not adjacent"), expected)
  end

  test "no-op when already grouped" do
    input = """
    defmodule AlreadyGrouped do
      def foo(1), do: :a
      def foo(2), do: :b
      def bar(), do: :ok
    end
    """

    result = fix(input, "function foo/1 has multiple clauses and they are not adjacent")
    confirm_fix(result, input)
  end
end
