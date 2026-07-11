defmodule Credence.Semantic.FixUndefinedVariableInHelperScopeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUndefinedVariableInHelperScope

  @message "undefined variable \"state\""

  defp fix(source, message, line \\ 1) do
    FixUndefinedVariableInHelperScope.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "adds field as parameter to defp and passes from call site" do
    input = ~S"""
    defmodule TreeStream do
      use GenServer

      @impl true
      def init(opts) do
        state = %{nodes: %{}, order: [], strategy: :discard}
        {:ok, state}
      end

      @impl true
      def handle_call(:forest, _from, state) do
        result = build_node_tree(state.nodes, :root)
        {:reply, result, state}
      end

      @impl true
      def handle_call(_msg, _from, state) do
        {:reply, :ok, state}
      end

      defp build_node_tree(nodes, id) do
        node = Map.fetch!(nodes, id)
        ordered_children = Enum.filter(state.order, fn c -> c.parent_id == id end)
        Map.put(node, :children, ordered_children)
      end
    end
    """

    expected = ~S"""
    defmodule TreeStream do
      use GenServer

      @impl true
      def init(opts) do
        state = %{nodes: %{}, order: [], strategy: :discard}
        {:ok, state}
      end

      @impl true
      def handle_call(:forest, _from, state) do
        result = build_node_tree(state.nodes, state.order, :root)
        {:reply, result, state}
      end

      @impl true
      def handle_call(_msg, _from, state) do
        {:reply, :ok, state}
      end

      defp build_node_tree(nodes, order, id) do
        node = Map.fetch!(nodes, id)
        ordered_children = Enum.filter(order, fn c -> c.parent_id == id end)
        Map.put(node, :children, ordered_children)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule TreeStream do
      use GenServer

      @impl true
      def init(opts) do
        state = %{nodes: %{}, order: [], strategy: :discard}
        {:ok, state}
      end

      @impl true
      def handle_call(:forest, _from, state) do
        result = build_node_tree(state.nodes, :root)
        {:reply, result, state}
      end

      defp build_node_tree(nodes, id) do
        node = Map.fetch!(nodes, id)
        ordered_children = Enum.filter(state.order, fn c -> c.parent_id == id end)
        Map.put(node, :children, ordered_children)
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no helper scope pattern found" do
    input = ~S"""
    defmodule NoMatch do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, @message, 3)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated undefined variable" do
    input = ~S"""
    defmodule NoMatch do
      def test do
        IO.puts(y)
      end
    end
    """

    result = fix(input, "undefined variable \"y\"", 3)
    confirm_fix(result, input)
  end
end
