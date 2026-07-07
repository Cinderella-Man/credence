defmodule Credence.Semantic.NoHallucinatedStructFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedStruct

  @message "Task.ExitError.__struct__/1 is undefined, cannot expand struct Task.ExitError"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedStruct.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces hallucinated struct with tuple" do
    input = """
    defmodule HallucinatedStructExample do
      use GenServer

      def init(state) do
        {:ok, state}
      end

      def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
        error_result = {:error, {:exception, %Task.ExitError{reason: reason}}}
        {:noreply, Map.put(state, :last_error, error_result)}
      end

      def handle_info(_, state), do: {:noreply, state}
    end
    """

    expected = """
    defmodule HallucinatedStructExample do
      use GenServer

      def init(state) do
        {:ok, state}
      end

      def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
        error_result = {:error, {:exception, {Task.ExitError, reason}}}
        {:noreply, Map.put(state, :last_error, error_result)}
      end

      def handle_info(_, state), do: {:noreply, state}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule HallucinatedStructExample do
      use GenServer

      def init(state) do
        {:ok, state}
      end

      def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
        error_result = {:error, {:exception, %Task.ExitError{reason: reason}}}
        {:noreply, Map.put(state, :last_error, error_result)}
      end

      def handle_info(_, state), do: {:noreply, state}
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when struct is defined in the source" do
    input = """
    defmodule MyStruct do
      defstruct [:field]
    end

    defmodule Example do
      def test do
        %MyStruct{field: "value"}
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
