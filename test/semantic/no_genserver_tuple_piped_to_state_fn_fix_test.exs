defmodule Credence.Semantic.NoGenserverTuplePipedToStateFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoGenserverTuplePipedToStateFn

  @match_message "GenServer reply tuple piped into helper function"

  defp fix(source, message, line \\ 1) do
    NoGenserverTuplePipedToStateFn.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes noreply tuple piped into helper" do
    input = """
    defmodule GenServerPipeTupleExample do
      use GenServer

      def start_link(_opts), do: GenServer.start_link(__MODULE__, %{})

      @impl true
      def init(_), do: {:ok, %{count: 0}}

      @impl true
      def handle_cast(:increment, state) do
        {:noreply, %{state | count: state.count + 1}}
        |> maybe_process()
      end

      defp maybe_process(state) do
        IO.puts("count is \#{state.count}")
        state
      end
    end
    """

    expected = """
    defmodule GenServerPipeTupleExample do
      use GenServer

      def start_link(_opts), do: GenServer.start_link(__MODULE__, %{})

      @impl true
      def init(_), do: {:ok, %{count: 0}}

      @impl true
      def handle_cast(:increment, state) do
        {:noreply, maybe_process(%{state | count: state.count + 1})}
      end

      defp maybe_process(state) do
        IO.puts("count is \#{state.count}")
        state
      end
    end
    """

    confirm_fix(fix(input, @match_message, 11), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      use GenServer

      def init(_), do: {:ok, %{count: 0}}

      def handle_cast(:increment, state) do
        {:noreply, %{state | count: state.count + 1}}
        |> maybe_process()
      end

      defp maybe_process(state), do: state
    end
    """

    assert valid_syntax?(fix(input, @match_message, 8))
  end

  test "returns source unchanged when no pipe into tuple" do
    input = """
    defmodule Example do
      use GenServer

      def init(_), do: {:ok, %{count: 0}}

      def handle_cast(:increment, state) do
        {:noreply, maybe_process(%{state | count: state.count + 1})}
      end

      defp maybe_process(state), do: state
    end
    """

    confirm_fix(fix(input, @match_message, 8), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @match_message), input)
  end
end
