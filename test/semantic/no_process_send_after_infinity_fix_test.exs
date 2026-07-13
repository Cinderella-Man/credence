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

  test "adds when guard and catch-all for variable timeout" do
    input = """
    defmodule VariableInterval do
      def schedule_cleanup(interval) do
        Process.send_after(self(), :tick, interval)
      end
    end
    """

    expected = """
    defmodule VariableInterval do
      def schedule_cleanup(interval) when interval != :infinity do
        Process.send_after(self(), :tick, interval)
      end

      def schedule_cleanup(_interval), do: :ok
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "adds when guard and catch-all for variable timeout (dot access)" do
    input = """
    defmodule Clean do
      def schedule_cleanup(state) do
        ref = Process.send_after(self(), :cleanup, state.interval)
        %{state | cleanup_ref: ref}
      end
    end
    """

    expected = """
    defmodule Clean do
      def schedule_cleanup(state) when state.interval != :infinity do
        ref = Process.send_after(self(), :cleanup, state.interval)
        %{state | cleanup_ref: ref}
      end

      def schedule_cleanup(_state), do: :ok
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "adds when guard and catch-all for variable :infinity via helper" do
    input = """
    defmodule TestProcessSendAfterVariableInfinity do
      def schedule_cleanup(interval_ms) do
        Process.send_after(self(), :cleanup, interval_ms)
      end

      def init do
        interval = get_interval()
        schedule_cleanup(interval)
        :ok
      end

      defp get_interval, do: :infinity
    end
    """

    expected = """
    defmodule TestProcessSendAfterVariableInfinity do
      def schedule_cleanup(interval_ms) when interval_ms != :infinity do
        Process.send_after(self(), :cleanup, interval_ms)
      end

      def schedule_cleanup(_interval_ms), do: :ok

      def init do
        interval = get_interval()
        schedule_cleanup(interval)
        :ok
      end

      defp get_interval, do: :infinity
    end
    """

    confirm_fix(fix(input, @real_message), expected)
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
