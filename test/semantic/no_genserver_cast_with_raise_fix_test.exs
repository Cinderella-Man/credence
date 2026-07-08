defmodule Credence.Semantic.NoGenserverCastWithRaiseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoGenserverCastWithRaise

  @real_message ~s(got "@impl true" for function init/1 but no behaviour was declared)

  defp fix(source, message \\ @real_message, line \\ 1) do
    NoGenserverCastWithRaise.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "converts handle_cast with raise to handle_call" do
    input = """
    defmodule LWWSet do
      def add(server, element, timestamp),
        do: GenServer.cast(server, {:add, element, timestamp})

      def remove(server, element, timestamp),
        do: GenServer.cast(server, {:remove, element, timestamp})

      @impl true
      def handle_cast({:add, element, timestamp}, %{adds: adds} = state) do
        unless is_integer(timestamp) and timestamp > 0 do
          raise ArgumentError, "Timestamp must be a positive integer"
        end

        {:noreply, %{state | adds: Map.put(adds, element, timestamp)}}
      end

      def handle_cast({:remove, element, timestamp}, %{removes: removes} = state) do
        unless is_integer(timestamp) and timestamp > 0 do
          raise ArgumentError, "Timestamp must be a positive integer"
        end

        {:noreply, %{state | removes: Map.put(removes, element, timestamp)}}
      end
    end
    """

    expected = """
    defmodule LWWSet do
      def add(server, element, timestamp),
        do: GenServer.call(server, {:add, element, timestamp})

      def remove(server, element, timestamp),
        do: GenServer.call(server, {:remove, element, timestamp})

      @impl true
      def handle_call({:add, element, timestamp}, _from, %{adds: adds} = state) do
        unless is_integer(timestamp) and timestamp > 0 do
          raise ArgumentError, "Timestamp must be a positive integer"
        end

        {:reply, :ok, %{state | adds: Map.put(adds, element, timestamp)}}
      end

      def handle_call({:remove, element, timestamp}, _from, %{removes: removes} = state) do
        unless is_integer(timestamp) and timestamp > 0 do
          raise ArgumentError, "Timestamp must be a positive integer"
        end

        {:reply, :ok, %{state | removes: Map.put(removes, element, timestamp)}}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not touch handle_cast without raise" do
    input = """
    defmodule Clean do
      def ping(server), do: GenServer.cast(server, :ping)

      @impl true
      def handle_cast(:ping, state) do
        {:noreply, Map.put(state, :pinged, true)}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not touch handle_call" do
    input = """
    defmodule QueryModule do
      def query(server), do: GenServer.call(server, :query)

      @impl true
      def handle_call(:query, _from, state) do
        {:reply, state, state}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Simple do
      def go(server), do: GenServer.cast(server, :go)

      @impl true
      def handle_cast(:go, state) do
        raise "boom"
        {:noreply, state}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end

  test "only transforms handle_cast clauses that contain raise" do
    input = """
    defmodule Mixed do
      def add(server, val), do: GenServer.cast(server, {:add, val})
      def log(server, msg), do: GenServer.cast(server, {:log, msg})

      @impl true
      def handle_cast({:add, val}, state) do
        if val < 0, do: raise(ArgumentError, "negative")
        {:noreply, Map.put(state, :val, val)}
      end

      @impl true
      def handle_cast({:log, msg}, state) do
        IO.puts(msg)
        {:noreply, state}
      end
    end
    """

    result = fix(input)
    assert valid_syntax?(result)
    # GenServer.cast → GenServer.call happens globally
    refute result =~ "GenServer.cast"
    # The handle_cast with raise becomes handle_call
    assert result =~ "handle_call"
  end
end
