defmodule Credence.Semantic.NoSendSelfInTaskFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoSendSelfInTask

  @real_message "send(self(), ...) called inside a Task callback; self() refers to the task process, not the parent"

  defp fix(source, message \\ @real_message, line \\ 21) do
    NoSendSelfInTask.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "captures parent = self() and replaces self() inside Task.start_link" do
    input = """
    defmodule Cache do
      use GenServer

      defstruct value: nil

      def start_link, do: GenServer.start_link(__MODULE__, %__MODULE__{})

      def get(pid), do: GenServer.call(pid, :get)

      def refresh(pid) do
        GenServer.call(pid, :refresh)
      end

      @impl true
      def init(state), do: {:ok, state}

      @impl true
      def handle_call(:get, _from, state), do: {:reply, state.value, state}

      def handle_call(:refresh, _from, state) do
        Task.start_link(fn ->
          new_value = expensive_fetch()
          send(self(), {:refreshed, new_value})
        end)

        {:reply, :ok, state}
      end

      @impl true
      def handle_info({:refreshed, new_value}, state) do
        {:noreply, %{state | value: new_value}}
      end

      defp expensive_fetch, do: 42
    end
    """

    expected = """
    defmodule Cache do
      use GenServer

      defstruct value: nil

      def start_link, do: GenServer.start_link(__MODULE__, %__MODULE__{})

      def get(pid), do: GenServer.call(pid, :get)

      def refresh(pid) do
        GenServer.call(pid, :refresh)
      end

      @impl true
      def init(state), do: {:ok, state}

      @impl true
      def handle_call(:get, _from, state), do: {:reply, state.value, state}

      def handle_call(:refresh, _from, state) do
        parent = self()

        Task.start_link(fn ->
          new_value = expensive_fetch()
          send(parent, {:refreshed, new_value})
        end)

        {:reply, :ok, state}
      end

      @impl true
      def handle_info({:refreshed, new_value}, state) do
        {:noreply, %{state | value: new_value}}
      end

      defp expensive_fetch, do: 42
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def refresh(pid) do
        Task.start_link(fn ->
          send(self(), {:refreshed, 42})
        end)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 4))
  end

  test "returns source unchanged when no Task callback present" do
    input = """
    defmodule Example do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when self() is outside a Task callback" do
    input = """
    defmodule Example do
      def send_to_self do
        send(self(), :hello)
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "works with Task.async" do
    input = """
    defmodule Example do
      def fetch(pid) do
        Task.async(fn ->
          result = expensive()
          send(self(), {:done, result})
        end)
      end

      defp expensive, do: 42
    end
    """

    expected = """
    defmodule Example do
      def fetch(pid) do
        parent = self()

        Task.async(fn ->
          result = expensive()
          send(parent, {:done, result})
        end)
      end

      defp expensive, do: 42
    end
    """

    confirm_fix(fix(input, @real_message, 4), expected)
  end
end
