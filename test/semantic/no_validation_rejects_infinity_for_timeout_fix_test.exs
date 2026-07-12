defmodule Credence.Semantic.NoValidationRejectsInfinityForTimeoutFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoValidationRejectsInfinityForTimeout

  @match_msg "must be a positive integer"

  defp fix(source, message, line \\ 1) do
    NoValidationRejectsInfinityForTimeout.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the validation guard to allow :infinity" do
    input = """
    defmodule SharedPoolBucket do
      use GenServer

      def start_link(opts) do
        cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, 60_000)

        unless is_integer(cleanup_interval_ms) and cleanup_interval_ms > 0 do
          raise ArgumentError, ":cleanup_interval_ms must be a positive integer"
        end

        state = %{cleanup_interval_ms: cleanup_interval_ms}
        GenServer.start_link(__MODULE__, state)
      end

      @impl true
      def init(state) do
        if state.cleanup_interval_ms != :infinity do
          Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
        end
        {:ok, state}
      end

      @impl true
      def handle_info(:cleanup, state) do
        if state.cleanup_interval_ms != :infinity do
          Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
        end
        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule SharedPoolBucket do
      use GenServer

      def start_link(opts) do
        cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, 60_000)

        unless (is_integer(cleanup_interval_ms) and cleanup_interval_ms > 0) or
          cleanup_interval_ms == :infinity do
          raise ArgumentError, ":cleanup_interval_ms must be a positive integer or :infinity"
        end

        state = %{cleanup_interval_ms: cleanup_interval_ms}
        GenServer.start_link(__MODULE__, state)
      end

      @impl true
      def init(state) do
        if state.cleanup_interval_ms != :infinity do
          Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
        end
        {:ok, state}
      end

      @impl true
      def handle_info(:cleanup, state) do
        if state.cleanup_interval_ms != :infinity do
          Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
        end
        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input, @match_msg), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule SharedPoolBucket do
      use GenServer

      def start_link(opts) do
        cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, 60_000)

        unless is_integer(cleanup_interval_ms) and cleanup_interval_ms > 0 do
          raise ArgumentError, ":cleanup_interval_ms must be a positive integer"
        end

        state = %{cleanup_interval_ms: cleanup_interval_ms}
        GenServer.start_link(__MODULE__, state)
      end
    end
    """

    assert valid_syntax?(fix(input, @match_msg))
  end

  test "returns source unchanged when no validation guard found" do
    input = """
    defmodule Clean do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @match_msg), input)
  end

  test "returns source unchanged when validation already allows :infinity" do
    input = """
    defmodule AlreadyFixed do
      def start_link(opts) do
        timeout = Keyword.get(opts, :timeout, 5_000)

        unless (is_integer(timeout) and timeout > 0) or timeout == :infinity do
          raise ArgumentError, "timeout must be a positive integer or :infinity"
        end

        {:ok, timeout}
      end
    end
    """

    confirm_fix(fix(input, @match_msg), input)
  end
end
