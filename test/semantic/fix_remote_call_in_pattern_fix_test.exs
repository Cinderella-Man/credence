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

  test "fixes the case pattern" do
    input = ~S"""
    defmodule Ex do
      def check(state, msg) do
        case msg do
          {state.ref, result} -> result
          _ -> :ignore
        end
      end
    end
    """

    expected = ~S"""
    defmodule Ex do
      def check(state, msg) do
        ref = state.ref

        case msg do
          {^ref, result} -> result
          _ -> :ignore
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 4), expected)
  end

  test "leaves guards untouched (dot access is valid in a guard, a pin is not)" do
    input = ~S"""
    defmodule Ex do
      def wait(state, x) do
        receive do
          {state.ref, :done, result} -> result
          other when other == state.ref -> :dup
        end
      end
    end
    """

    expected = ~S"""
    defmodule Ex do
      def wait(state, x) do
        ref = state.ref

        receive do
          {^ref, :done, result} -> result
          other when other == state.ref -> :dup
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 4), expected)
  end

  test "picks a fresh pin name when the field name is already a variable" do
    input = ~S"""
    defmodule Ex do
      def wait(state, ref) do
        receive do
          {state.ref, :done} -> ref
        end
      end
    end
    """

    expected = ~S"""
    defmodule Ex do
      def wait(state, ref) do
        ref_1 = state.ref

        receive do
          {^ref_1, :done} -> ref
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 4), expected)
  end

  test "no-ops on alias-receiver assignment (module attributes are not maps)" do
    input = ~S"""
    defmodule Ex do
      def f(x) do
        Config.Store.timeout = x
        send(Config.Store, :ping)
        x
      end
    end
    """

    confirm_fix(
      fix(input, "cannot invoke remote function Config.Store.timeout/0 inside a match", 3),
      input
    )
  end

  test "no-ops when the receiver is rebound after the assignment" do
    input = ~S"""
    defmodule Ex do
      def handle(state) do
        state.streams = %{}
        state = log(state)
        {:ok, state}
      end
    end
    """

    confirm_fix(
      fix(input, "cannot invoke remote function state.streams/0 inside a match", 3),
      input
    )
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
