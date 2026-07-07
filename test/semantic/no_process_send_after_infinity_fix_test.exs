defmodule Credence.Semantic.NoProcessSendAfterInfinityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoProcessSendAfterInfinity

  @real_message "redefining module SessionStore (current version loaded from _build/test/lib/workspace/ebin/Elixir.SessionStore.beam)"

  defp fix(source, message, line \\ 1) do
    NoProcessSendAfterInfinity.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces Process.send_after with :infinity timeout" do
    input = """
    defmodule ScheduleWithInfinity do
      def schedule_cleanup(state) do
        ref = Process.send_after(self(), :cleanup, :infinity)
        %{state | cleanup_ref: ref}
      end

      def schedule_periodic(msg, interval_ms) do
        Process.send_after(self(), msg, :infinity)
      end
    end
    """

    expected = """
    defmodule ScheduleWithInfinity do
      def schedule_cleanup(state) do
        # :infinity is not a valid argument for :erlang.send_after/3;
        # skip scheduling to avoid runtime crash.
        :ok
      end

      def schedule_periodic(msg, interval_ms) do
        # :infinity is not a valid argument for :erlang.send_after/3;
        # skip scheduling to avoid runtime crash.
        :ok
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ScheduleWithInfinity do
      def schedule_cleanup(state) do
        ref = Process.send_after(self(), :cleanup, :infinity)
        %{state | cleanup_ref: ref}
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no Process.send_after with :infinity" do
    input = """
    defmodule Clean do
      def schedule_cleanup(state) do
        ref = Process.send_after(self(), :cleanup, state.interval)
        %{state | cleanup_ref: ref}
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
