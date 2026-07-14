defmodule Credence.Semantic.NoRaiseInHandleCallFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRaiseInHandleCall

  @real_message "raise in handle_call — use {:reply, {:error, msg}, state} instead"

  defp fix(source, message \\ @real_message, line \\ 1) do
    NoRaiseInHandleCall.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces raise with {:reply, {:error, msg}, state} in handle_call" do
    input = """
    defmodule ORSet do
      use GenServer

      def start_link(opts \\\\ []) do
        name = Keyword.get(opts, :name)
        GenServer.start_link(__MODULE__, :ok, name: name)
      end

      def remove(server, element) do
        GenServer.call(server, {:remove, element})
      end

      @impl GenServer
      def init(:ok), do: {:ok, %{entries: %{}}}

      @impl GenServer
      def handle_call({:remove, element}, _from, state) do
        case Map.fetch(state.entries, element) do
          :error ->
            raise ArgumentError, "element \#{inspect(element)} is not in the set"
          {:ok, _tags} ->
            {:reply, :ok, state}
        end
      end
    end
    """

    expected = """
    defmodule ORSet do
      use GenServer

      def start_link(opts \\\\ []) do
        name = Keyword.get(opts, :name)
        GenServer.start_link(__MODULE__, :ok, name: name)
      end

      def remove(server, element) do
        GenServer.call(server, {:remove, element})
      end

      @impl GenServer
      def init(:ok), do: {:ok, %{entries: %{}}}

      @impl GenServer
      def handle_call({:remove, element}, _from, state) do
        case Map.fetch(state.entries, element) do
          :error ->
            {:reply, {:error, "element \#{inspect(element)} is not in the set"}, state}

          {:ok, _tags} ->
            {:reply, :ok, state}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "replaces raise with module and string message" do
    input = """
    defmodule MyServer do
      use GenServer

      def handle_call(:bad, _from, state) do
        raise RuntimeError, "something went wrong"
      end
    end
    """

    expected = """
    defmodule MyServer do
      use GenServer

      def handle_call(:bad, _from, state) do
        {:reply, {:error, "something went wrong"}, state}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "replaces raise with plain string message" do
    input = """
    defmodule MyServer do
      use GenServer

      def handle_call(:bad, _from, state) do
        raise "bad things happened"
      end
    end
    """

    expected = """
    defmodule MyServer do
      use GenServer

      def handle_call(:bad, _from, state) do
        {:reply, {:error, "bad things happened"}, state}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "returns source unchanged when no raise in handle_call" do
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

  test "returns source unchanged when raise is outside handle_call" do
    input = """
    defmodule OtherModule do
      def helper do
        raise ArgumentError, "not in handle_call"
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

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule MyServer do
      use GenServer

      def handle_call(:bad, _from, state) do
        raise RuntimeError, "error"
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
