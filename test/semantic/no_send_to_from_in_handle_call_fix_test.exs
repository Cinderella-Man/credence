defmodule Credence.Semantic.NoSendToFromInHandleCallFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoSendToFromInHandleCall

  @real_message "send/2 called with handle_call from — use GenServer.reply/2 instead"

  defp fix(source, message \\ @real_message, line \\ 1) do
    NoSendToFromInHandleCall.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces send(from, msg) with GenServer.reply(from, msg) in handle_call and handle_info" do
    input = """
    defmodule SendToFromExample do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts)
      end

      def drain(server) do
        GenServer.call(server, :drain)
      end

      @impl true
      def init(_opts), do: {:ok, %{waiting: false, from: nil, queue: []}}

      @impl true
      def handle_call(:drain, from, %{queue: queue} = state) do
        if Enum.empty?(queue) do
          send(from, :ok)
          {:noreply, state}
        else
          {:noreply, %{state | waiting: true, from: from}}
        end
      end

      @impl true
      def handle_info(:done, %{waiting: true, from: from} = state) do
        send(from, :ok)
        {:noreply, %{state | waiting: false, from: nil}}
      end

      def handle_info(_, state), do: {:noreply, state}
    end
    """

    expected = """
    defmodule SendToFromExample do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts)
      end

      def drain(server) do
        GenServer.call(server, :drain)
      end

      @impl true
      def init(_opts), do: {:ok, %{waiting: false, from: nil, queue: []}}

      @impl true
      def handle_call(:drain, from, %{queue: queue} = state) do
        if Enum.empty?(queue) do
          GenServer.reply(from, :ok)
          {:noreply, state}
        else
          {:noreply, %{state | waiting: true, from: from}}
        end
      end

      @impl true
      def handle_info(:done, %{waiting: true, from: from} = state) do
        GenServer.reply(from, :ok)
        {:noreply, %{state | waiting: false, from: nil}}
      end

      def handle_info(_, state), do: {:noreply, state}
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "replaces send(from, msg) with a complex message argument" do
    input = """
    defmodule ComplexMsg do
      use GenServer

      def handle_call(:query, from, state) do
        send(from, {:result, state.data, :extra})
        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule ComplexMsg do
      use GenServer

      def handle_call(:query, from, state) do
        GenServer.reply(from, {:result, state.data, :extra})
        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "returns source unchanged when no send(from, ...)" do
    input = """
    defmodule CleanModule do
      use GenServer

      def handle_call(:query, _from, state) do
        {:reply, state, state}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not replace send with other first argument" do
    input = """
    defmodule OtherSend do
      use GenServer

      def handle_call(:query, from, state) do
        send(self(), {:done, :ok})
        {:reply, :ok, state}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      use GenServer

      def handle_call(:drain, from, state) do
        send(from, :ok)
        {:noreply, state}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
