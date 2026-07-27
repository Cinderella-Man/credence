defmodule Credence.Semantic.NoRawSendInGenserverHandleCallFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRawSendInGenserverHandleCall

  @real_message "send/2 spawned from handle_call/3 — use GenServer.reply/2 instead"

  defp fix(source, message \\ @real_message, line \\ 1) do
    NoRawSendInGenserverHandleCall.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces send(caller_pid, result) with GenServer.reply(from, result) in spawn_link" do
    input = """
    defmodule BrokenReply do
      use GenServer

      def start_link(_opts), do: GenServer.start_link(__MODULE__, %{})
      def execute(server, key, func), do: GenServer.call(server, {:execute, key, func})

      @impl true
      def init(state), do: {:ok, state}

      @impl true
      def handle_call({:execute, key, func}, {caller_pid, _}, state) do
        task_ref = make_ref()

        spawn_link(fn ->
          result =
            try do
              {:ok, func.()}
            rescue
              e in RuntimeError ->
                {:error, {:exception, e}}
            end

          send(caller_pid, {:keyed_pool_result, task_ref, result})
        end)

        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule BrokenReply do
      use GenServer

      def start_link(_opts), do: GenServer.start_link(__MODULE__, %{})
      def execute(server, key, func), do: GenServer.call(server, {:execute, key, func})

      @impl true
      def init(state), do: {:ok, state}

      @impl true
      def handle_call({:execute, key, func}, {caller_pid, _} = from, state) do
        task_ref = make_ref()

        spawn_link(fn ->
          result =
            try do
              {:ok, func.()}
            rescue
              e in RuntimeError ->
                {:error, {:exception, e}}
            end

          GenServer.reply(from, {:keyed_pool_result, task_ref, result})
        end)

        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes a simple handle_call with send inside spawn" do
    input = """
    defmodule SimpleReply do
      use GenServer

      def handle_call(:query, {caller, _}, state) do
        spawn(fn ->
          send(caller, {:result, state})
        end)

        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule SimpleReply do
      use GenServer

      def handle_call(:query, {caller, _} = from, state) do
        spawn(fn ->
          GenServer.reply(from, {:result, state})
        end)

        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes send inside Task.async" do
    input = """
    defmodule TaskReply do
      use GenServer

      def handle_call(:work, {pid, _}, state) do
        Task.async(fn ->
          send(pid, :done)
        end)

        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule TaskReply do
      use GenServer

      def handle_call(:work, {pid, _} = from, state) do
        Task.async(fn ->
          GenServer.reply(from, :done)
        end)

        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "returns source unchanged when no send in handle_call" do
    input = """
    defmodule CleanModule do
      use GenServer

      def handle_call(:query, {pid, _}, state) do
        {:reply, state, state}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when send is not inside a spawn" do
    input = """
    defmodule DirectSend do
      use GenServer

      def handle_call(:query, {pid, _}, state) do
        send(pid, {:result, state})
        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when from_arg already has binding" do
    input = """
    defmodule AlreadyBound do
      use GenServer

      def handle_call(:query, {pid, _} = _from, state) do
        spawn(fn ->
          send(pid, {:result, state})
        end)

        {:noreply, state}
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

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule BrokenReply do
      use GenServer

      def handle_call(:query, {caller, _}, state) do
        spawn_link(fn ->
          send(caller, {:result, state})
        end)

        {:noreply, state}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
