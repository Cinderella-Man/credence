defmodule Credence.Semantic.NoHallucinatedSelfBangFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedSelfBang

  @real_message "undefined function self!/1 (expected CancellablePriorityQueue to define such a function or for it to be imported, but none are available)"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedSelfBang.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces self!(arg) with send(self(), arg)" do
    input = """
    defmodule M do
      use GenServer

      def handle_call({:go}, _from, s) do
        self!(:process_next)
        {:reply, :ok, s}
      end

      def handle_info(:process_next, s), do: {:noreply, s}
    end
    """

    expected = """
    defmodule M do
      use GenServer

      def handle_call({:go}, _from, s) do
        send(self(), :process_next)
        {:reply, :ok, s}
      end

      def handle_info(:process_next, s), do: {:noreply, s}
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      use GenServer

      def handle_call({:go}, _from, s) do
        self!(:process_next)
        {:reply, :ok, s}
      end

      def handle_info(:process_next, s), do: {:noreply, s}
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no self! present" do
    input = """
    defmodule M do
      use GenServer

      def handle_call({:go}, _from, s) do
        send(self(), :process_next)
        {:reply, :ok, s}
      end

      def handle_info(:process_next, s), do: {:noreply, s}
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "rewrites every single-arg self! occurrence in the file" do
    input = """
    self!(:a)
    foo()
    self!(:b)
    """

    expected = """
    send(self(), :a)
    foo()
    send(self(), :b)
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "leaves self!/2 untouched (send/3 would not compile)" do
    input = "self!(a, b)"

    confirm_fix(fix(input, @real_message), input)
  end

  test "leaves self!/0 untouched (send/1 would not compile)" do
    input = "self!()"

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
