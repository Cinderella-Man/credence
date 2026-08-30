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

  test "fixes function-head, anonymous-function, and with patterns" do
    function_input = ~S"""
    defmodule RemotePatternFunctionHeadRegression do
      def same?(state.ref, state), do: true
      def same?(_, _), do: false
    end
    """

    function_expected = ~S"""
    defmodule RemotePatternFunctionHeadRegression do
      def same?(ref, state) when ref == state.ref, do: true
      def same?(_, _), do: false
    end
    """

    anonymous_input = ~S"""
    defmodule RemotePatternAnonymousRegression do
      def matcher(state) do
        fn
          {state.ref, value} -> value
          _ -> :no_match
        end
      end
    end
    """

    anonymous_expected = ~S"""
    defmodule RemotePatternAnonymousRegression do
      def matcher(state) do
        ref = state.ref

        fn
          {^ref, value} -> value
          _ -> :no_match
        end
      end
    end
    """

    with_input = ~S"""
    defmodule RemotePatternWithRegression do
      def same?(state, value) do
        with state.ref <- value, do: true
      end
    end
    """

    with_expected = ~S"""
    defmodule RemotePatternWithRegression do
      def same?(state, value) do
        ref = state.ref
        with ^ref <- value, do: true
      end
    end
    """

    function_actual = fix(function_input, @real_message, 2)
    anonymous_actual = fix(anonymous_input, @real_message, 4)
    with_actual = fix(with_input, @real_message, 3)

    confirm_fix(function_actual, function_expected)
    confirm_fix(anonymous_actual, anonymous_expected)
    confirm_fix(with_actual, with_expected)

    assert Credence.RuleHelpers.compile_and_capture(function_actual) ==
             Credence.RuleHelpers.compile_and_capture(function_expected)

    assert Credence.RuleHelpers.compile_and_capture(anonymous_actual) ==
             Credence.RuleHelpers.compile_and_capture(anonymous_expected)

    assert Credence.RuleHelpers.compile_and_capture(with_actual) ==
             Credence.RuleHelpers.compile_and_capture(with_expected)
  end

  test "assignment updates later bare and field receiver reads consistently" do
    input = ~S"""
    defmodule RemotePatternAssignmentReadRegression do
      def update(state, value) do
        state.field = value
        {state, state.field}
      end
    end
    """

    expected = ~S"""
    defmodule RemotePatternAssignmentReadRegression do
      def update(state, value) do
        new_field = value
        {%{state | field: new_field}, new_field}
      end
    end
    """

    actual =
      fix(input, "cannot invoke remote function state.field/0 inside a match", 3)

    confirm_fix(actual, expected)

    assert Credence.RuleHelpers.compile_and_capture(actual) ==
             Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "does not rewrite matching assignment syntax inside quote" do
    input = ~S"""
    defmodule RemotePatternQuoteRegression do
      def matcher(state) do
        quoted =
          quote do
            state.ref = :quoted
            state
          end

        receive do
          {state.ref, value} -> {quoted, value}
        end
      end
    end
    """

    expected = ~S"""
    defmodule RemotePatternQuoteRegression do
      def matcher(state) do
        quoted =
          quote do
            state.ref = :quoted
            state
          end

        (
          ref = state.ref

          receive do
            {^ref, value} -> {quoted, value}
          end
        )
      end
    end
    """

    confirm_fix(fix(input, @real_message, 10), expected)
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
