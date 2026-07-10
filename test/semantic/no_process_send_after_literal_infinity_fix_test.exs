defmodule Credence.Semantic.NoProcessSendAfterLiteralInfinityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoProcessSendAfterLiteralInfinity

  @real_message "variable acc in code block has no effect as it is never returned (remove the variable or assign it to _ to avoid warnings)"

  defp fix(source, message, line \\ 1) do
    NoProcessSendAfterLiteralInfinity.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "wraps Process.send_after in if guard when timeout is a variable" do
    input = """
    defmodule TestModule do
      use GenServer

      @impl true
      def init(opts) do
        interval = Keyword.get(opts, :interval, :infinity)
        Process.send_after(self(), :tick, interval)
        {:ok, %{}}
      end

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts)
      end

      @impl true
      def handle_info(:tick, state) do
        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule TestModule do
      use GenServer

      @impl true
      def init(opts) do
        interval = Keyword.get(opts, :interval, :infinity)
        if interval != :infinity do
          Process.send_after(self(), :tick, interval)
        end
        {:ok, %{}}
      end

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts)
      end

      @impl true
      def handle_info(:tick, state) do
        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TestModule do
      def init(opts) do
        interval = Keyword.get(opts, :interval, :infinity)
        Process.send_after(self(), :tick, interval)
        {:ok, %{}}
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no Process.send_after with variable timeout" do
    input = """
    defmodule Clean do
      def schedule_cleanup do
        Process.send_after(self(), :cleanup, 5000)
        :ok
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
