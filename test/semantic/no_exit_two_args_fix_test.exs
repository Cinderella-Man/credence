defmodule Credence.Semantic.NoExitTwoArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoExitTwoArgs

  @real_message "undefined function exit/2 (expected TimeoutWorker to define such a function or for it to be imported, but none are available)"

  defp fix(source, message, line \\ 1) do
    NoExitTwoArgs.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "fixes exit/2 to Process.exit/2" do
    input = """
    defmodule TimeoutWorker do
      use GenServer

      @impl true
      def handle_info(:timeout_check, state) do
        exit(self(), :timeout_task)
        {:noreply, state}
      end
    end
    """

    expected = """
    defmodule TimeoutWorker do
      use GenServer

      @impl true
      def handle_info(:timeout_check, state) do
        Process.exit(self(), :timeout_task)
        {:noreply, state}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 6), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TimeoutWorker do
      use GenServer

      @impl true
      def handle_info(:timeout_check, state) do
        exit(self(), :timeout_task)
        {:noreply, state}
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 6))
  end

  test "returns source unchanged when no exit/2 call on the flagged line" do
    input = """
    defmodule Clean do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message, 2), input)
  end

  test "only replaces on the flagged line, not other lines" do
    input = """
    defmodule Multi do
      def a, do: exit(self(), :reason)
      def b, do: exit(self(), :other)
    end
    """

    expected = """
    defmodule Multi do
      def a, do: Process.exit(self(), :reason)
      def b, do: exit(self(), :other)
    end
    """

    confirm_fix(fix(input, @real_message, 2), expected)
  end
end
