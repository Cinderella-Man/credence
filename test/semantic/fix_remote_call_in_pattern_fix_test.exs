defmodule Credence.Semantic.FixRemoteCallInPatternFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixRemoteCallInPattern

  @real_message "cannot invoke remote function state.ref/0 inside a match"

  defp fix(source, message, line \\ 4) do
    FixRemoteCallInPattern.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the receive pattern" do
    input = ~S"""
    defmodule Example do
      def wait(state) do
        receive do
          {state.ref, :done, result} -> result
        end
      end
    end
    """

    expected = ~S"""
    defmodule Example do
      def wait(state) do
        ref = state.ref

        receive do
          {^ref, :done, result} -> result
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 4), expected)
  end

  test "fixes var.field = expr assignment to local variable + map update" do
    input = ~S"""
    defmodule ResetStreams do
      use GenServer

      def init(_), do: {:ok, %{streams: %{}}}

      def handle_call({:reset, name}, _from, state) do
        state.streams =
          case Map.get(state.streams, name) do
            nil -> state.streams
            _ -> Map.put(state.streams, name, %{})
          end

        {:reply, :ok, state}
      end
    end
    """

    expected = ~S"""
    defmodule ResetStreams do
      use GenServer

      def init(_), do: {:ok, %{streams: %{}}}

      def handle_call({:reset, name}, _from, state) do
        new_streams =
          case Map.get(state.streams, name) do
            nil -> state.streams
            _ -> Map.put(state.streams, name, %{})
          end

        {:reply, :ok, %{state | streams: new_streams}}
      end
    end
    """

    confirm_fix(
      fix(input, "cannot invoke remote function state.streams/0 inside a match", 7),
      expected
    )
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule Example do
      def wait(state) do
        receive do
          {state.ref, :done, result} -> result
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 4))
  end

  test "returns source unchanged when no remote call in pattern" do
    input = ~S"""
    defmodule Example do
      def wait(ref) do
        receive do
          {^ref, :done, result} -> result
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 4), input)
  end

  test "returns source unchanged for unrelated code" do
    input = ~S"""
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
