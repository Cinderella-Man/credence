defmodule Credence.Semantic.NoGenserverReplyInHandleCastFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoGenserverReplyInHandleCast

  @real_message "GenServer.reply/2 called inside handle_cast/2 — use send/2 instead"

  defp fix(source, message, line \\ 1) do
    NoGenserverReplyInHandleCast.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces GenServer.reply with send in a simple handle_cast" do
    input = """
    defmodule SimpleReply do
      use GenServer

      def init(state), do: {:ok, state}

      def handle_cast({:ping, caller}, state) do
        GenServer.reply(caller, :pong)
        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule SimpleReply do
      use GenServer

      def init(state), do: {:ok, state}

      def handle_cast({:ping, caller}, state) do
        send(caller, :pong)
        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 7), expected)
  end

  test "replaces multiple GenServer.reply calls in one handle_cast" do
    input = """
    defmodule BudgetRetryWorker do
      use GenServer

      def execute(server, func, opts \\\\ []) do
        correlation_id = make_ref()
        GenServer.cast(server, {:execute, self(), correlation_id, func, opts})
        receive do
          {^correlation_id, result} -> result
        end
      end

      @impl true
      def init(opts), do: {:ok, %{opts: opts}}

      @impl true
      def handle_cast({:execute, caller, correlation_id, func, opts}, state) do
        case func.() do
          {:ok, result} ->
            GenServer.reply(caller, {correlation_id, {:ok, result}})
            {:noreply, state}
          {:error, reason} ->
            budget_ms = Keyword.get(opts, :budget_ms, 30_000)
            GenServer.reply(caller, {correlation_id, {:error, :budget_exhausted, reason, 1}})
            {:noreply, state}
        end
      end
    end
    """

    expected = """
    defmodule BudgetRetryWorker do
      use GenServer

      def execute(server, func, opts \\\\ []) do
        correlation_id = make_ref()
        GenServer.cast(server, {:execute, self(), correlation_id, func, opts})

        receive do
          {^correlation_id, result} -> result
        end
      end

      @impl true
      def init(opts), do: {:ok, %{opts: opts}}

      @impl true
      def handle_cast({:execute, caller, correlation_id, func, opts}, state) do
        case func.() do
          {:ok, result} ->
            send(caller, {correlation_id, {:ok, result}})
            {:noreply, state}

          {:error, reason} ->
            budget_ms = Keyword.get(opts, :budget_ms, 30_000)
            send(caller, {correlation_id, {:error, :budget_exhausted, reason, 1}})
            {:noreply, state}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 17), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule SimpleReply do
      use GenServer

      def init(state), do: {:ok, state}

      def handle_cast({:ping, caller}, state) do
        GenServer.reply(caller, :pong)
        {:noreply, state}
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 7))
  end

  test "returns source unchanged when no GenServer.reply in handle_cast" do
    input = """
    defmodule CleanModule do
      use GenServer

      def init(state), do: {:ok, state}

      def handle_cast({:update, value}, state) do
        {:noreply, Map.put(state, :key, value)}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 7), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "does not touch GenServer.reply in handle_call" do
    input = """
    defmodule CallModule do
      use GenServer

      def init(state), do: {:ok, state}

      def handle_call({:query}, from, state) do
        GenServer.reply(from, :result)
        {:reply, :ok, state}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 7), input)
  end
end
