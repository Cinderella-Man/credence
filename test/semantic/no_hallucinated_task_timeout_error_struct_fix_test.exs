defmodule Credence.Semantic.NoHallucinatedTaskTimeoutErrorStructFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedTaskTimeoutErrorStruct

  @real_message "Task.TimeoutError.__struct__/1 is undefined, cannot expand struct Task.TimeoutError"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedTaskTimeoutErrorStruct.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces hallucinated Task.TimeoutError struct with :timeout" do
    input = """
    defmodule TaskTimeoutErrorExample do
      def stream_with_timeout(items) do
        items
        |> Task.async_stream(
          fn item -> process(item) end,
          ordered: true,
          timeout: 1000,
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, {%Task.TimeoutError{}, _stacktrace}} -> {:error, :timeout}
        end)
      end

      defp process(item), do: item
    end
    """

    expected = """
    defmodule TaskTimeoutErrorExample do
      def stream_with_timeout(items) do
        items
        |> Task.async_stream(
          fn item -> process(item) end,
          ordered: true,
          timeout: 1000,
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, :timeout} -> {:error, :timeout}
        end)
      end

      defp process(item), do: item
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TaskTimeoutErrorExample do
      def stream_with_timeout(items) do
        items
        |> Task.async_stream(
          fn item -> process(item) end,
          ordered: true,
          timeout: 1000,
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, {%Task.TimeoutError{}, _stacktrace}} -> {:error, :timeout}
        end)
      end

      defp process(item), do: item
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no hallucinated struct present" do
    input = """
    defmodule CleanExample do
      def stream_with_timeout(items) do
        items
        |> Task.async_stream(fn item -> process(item) end, timeout: 1000)
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, :timeout} -> {:error, :timeout}
        end)
      end

      defp process(item), do: item
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
