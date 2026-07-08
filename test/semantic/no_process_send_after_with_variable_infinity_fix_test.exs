defmodule Credence.Semantic.NoProcessSendAfterWithVariableInfinityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoProcessSendAfterWithVariableInfinity

  @real_message "invalid args for &, expected one of:\n\n  * &Mod.fun/arity to capture a remote function, such as &Enum.map/2\n  * &fun/arity to capture a local or imported function, such as &is_atom/1\n  * &some_code(&1, ...) containing at least one argument as &1, such as &List.flatten(&1)\n\nGot: System.monotonic_time(:millisecond) / 0"

  defp fix(source, message, line \\ 1) do
    NoProcessSendAfterWithVariableInfinity.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    defmodule ProcessSendAfterVarInfinity do
      use GenServer

      def start_link(opts \\\\ []) do
        cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, 60_000)
        GenServer.start_link(__MODULE__, cleanup_interval_ms)
      end

      @impl GenServer
      def init(cleanup_interval_ms) do
        Process.send_after(self(), :cleanup, cleanup_interval_ms)
        {:ok, %{cleanup_interval_ms: cleanup_interval_ms}}
      end

      @impl GenServer
      def handle_info(:cleanup, state) do
        Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule ProcessSendAfterVarInfinity do
      use GenServer

      def start_link(opts \\\\ []) do
        cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, 60_000)
        GenServer.start_link(__MODULE__, cleanup_interval_ms)
      end

      @impl GenServer
      def init(cleanup_interval_ms) do
        schedule_cleanup(cleanup_interval_ms)
        {:ok, %{cleanup_interval_ms: cleanup_interval_ms}}
      end

      @impl GenServer
      def handle_info(:cleanup, state) do
        schedule_cleanup(state.cleanup_interval_ms)
        {:noreply, state}
      end

      defp schedule_cleanup(:infinity), do: :ok
      defp schedule_cleanup(interval) when is_integer(interval) do
        Process.send_after(self(), :cleanup, interval)
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ProcessSendAfterVarInfinity do
      use GenServer

      def init(cleanup_interval_ms) do
        Process.send_after(self(), :cleanup, cleanup_interval_ms)
        {:ok, %{}}
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no Process.send_after with variable timeout" do
    input = """
    defmodule Clean do
      def schedule_cleanup(state) do
        ref = Process.send_after(self(), :cleanup, 5000)
        %{state | cleanup_ref: ref}
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
