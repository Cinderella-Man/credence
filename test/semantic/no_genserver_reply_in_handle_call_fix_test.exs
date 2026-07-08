defmodule Credence.Semantic.NoGenserverReplyInHandleCallFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoGenserverReplyInHandleCall

  @real_message "send/2 used to reply from handle_call/3 — use GenServer.reply/2 instead"

  defp fix(source, message \\ @real_message, line \\ 1) do
    NoGenserverReplyInHandleCall.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces send(caller_pid, result) with GenServer.reply(from, result) in handle_call" do
    input = """
    defmodule AsyncWorker do
      use GenServer

      def handle_call({:execute, key, func}, {caller_pid, _ref} = _from, state) do
        ref = make_ref()

        Task.start(fn ->
          result =
            try do
              case func.() do
                {:ok, value} -> {:ok, value}
                {:error, reason} -> {:error, reason}
                v -> {:ok, v}
              end
            rescue
              e ->
                {:error, {:exception, e}}
            after
              send(self(), {:task_done, key, ref})
            end

          send(caller_pid, result)
        end)

        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule AsyncWorker do
      use GenServer

      def handle_call({:execute, key, func}, {_, _} = from, state) do
        ref = make_ref()

        Task.start(fn ->
          result =
            try do
              case func.() do
                {:ok, value} -> {:ok, value}
                {:error, reason} -> {:error, reason}
                v -> {:ok, v}
              end
            rescue
              e ->
                {:error, {:exception, e}}
            after
              send(self(), {:task_done, key, ref})
            end

          GenServer.reply(from, result)
        end)

        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes a simple handle_call with send" do
    input = """
    defmodule SimpleReply do
      use GenServer

      def handle_call(:query, {caller, _} = _from, state) do
        send(caller, {:result, state})
        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule SimpleReply do
      use GenServer

      def handle_call(:query, {_, _} = from, state) do
        GenServer.reply(from, {:result, state})
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

  test "does not touch send(self(), ...) in after block" do
    input = """
    defmodule WithAfter do
      use GenServer

      def handle_call(:work, {pid, _} = _from, state) do
        Task.start(fn ->
          send(self(), {:done, :ok})
          send(pid, :result)
        end)

        {:noreply, state}
      end
    end
    """

    result = fix(input)
    assert valid_syntax?(result)
    # send(self(), ...) should remain, only send(pid, ...) should change
    assert result =~ "send(self(), {:done, :ok})"
    assert result =~ "GenServer.reply(from, :result)"
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule SimpleReply do
      use GenServer

      def handle_call(:query, {caller, _} = _from, state) do
        send(caller, :result)
        {:noreply, state}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
