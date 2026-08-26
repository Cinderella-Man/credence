defmodule Credence.Semantic.NoHallucinatedTaskTimeoutErrorStructFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedTaskTimeoutErrorStruct

  @real_message "struct Task.TimeoutError is undefined (module Task.TimeoutError is not available or is yet to be defined)"

  defp fix(source, message, line \\ 12) do
    NoHallucinatedTaskTimeoutErrorStruct.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 16}
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

  test "replaces only the pattern at the diagnostic position" do
    input = """
    defmodule TaskTimeoutTargetedNHTTES do
      def quoted, do: quote(do: {:exit, {%Task.TimeoutError{}, quoted_stacktrace}})
      def handle({:exit, {%Task.TimeoutError{}, _stacktrace}}), do: :timeout
      def data, do: {:exit, {%Task.TimeoutError{}, Runtime.stacktrace()}}
    end
    """

    expected = """
    defmodule TaskTimeoutTargetedNHTTES do
      def quoted, do: quote(do: {:exit, {%Task.TimeoutError{}, quoted_stacktrace}})
      def handle({:exit, :timeout}), do: :timeout
      def data, do: {:exit, {%Task.TimeoutError{}, Runtime.stacktrace()}}
    end
    """

    actual =
      NoHallucinatedTaskTimeoutErrorStruct.fix(input, %{
        severity: :error,
        message: "struct Task.TimeoutError is undefined",
        position: {3, 23}
      })

    confirm_fix(actual, expected)
  end

  test "expression-position diagnostics are not dispatched to this pattern fix" do
    input = """
    defmodule TaskTimeoutExpressionNHTTES do
      def value, do: %Task.TimeoutError{}
    end
    """

    result = Credence.fix(input)

    assert result.code == input

    refute Enum.any?(result.applied_rules, fn
             {NoHallucinatedTaskTimeoutErrorStruct, _status} -> true
             _ -> false
           end)
  end

  # ═══════════════════════════════════════════════════════════════════
  # THE WITNESS — the compiler's pattern-position diagnostic is the only
  # diagnostic this pattern-specific rule admits and repairs. docs/22 T5.9.
  # ═══════════════════════════════════════════════════════════════════

  describe "witnesses its own failure mode through the real pipeline" do
    setup do
      source = """
      defmodule TaskTimeoutWitnessCaseNHTTES do
        def run(stream) do
          Enum.map(stream, fn
            {:ok, v} -> v
            {:exit, {%Task.TimeoutError{}, _stacktrace}} -> :timeout
          end)
        end
      end
      """

      {:ok, source: source}
    end

    test "the compiler emits the pattern-position message for the documented shape", %{
      source: source
    } do
      diagnostics =
        case Credence.RuleHelpers.compile_and_capture(source) do
          {:ok, ds} -> ds
          {:error, ds} -> ds
        end

      assert Enum.any?(diagnostics, &NoHallucinatedTaskTimeoutErrorStruct.match?/1)

      assert Enum.map(diagnostics, & &1.message) == [@real_message]
    end

    test "it is repaired end-to-end through real dispatch", %{source: source} do
      result = Credence.fix(source)

      expected = """
      defmodule TaskTimeoutWitnessCaseNHTTES do
        def run(stream) do
          Enum.map(stream, fn
            {:ok, v} -> v
            {:exit, :timeout} -> :timeout
          end)
        end
      end
      """

      assert {NoHallucinatedTaskTimeoutErrorStruct, 1} in result.applied_rules
      confirm_fix(result.code, expected)
      assert Credence.RuleCase.compiles?(result.code)
    end

    test "the same shape in a function head also witnesses" do
      source = """
      defmodule TaskTimeoutWitnessHeadNHTTES do
        def handle({:exit, {%Task.TimeoutError{}, _stacktrace}}), do: :timeout
        def handle({:ok, v}), do: v
      end
      """

      result = Credence.fix(source)

      expected = """
      defmodule TaskTimeoutWitnessHeadNHTTES do
        def handle({:exit, :timeout}), do: :timeout
        def handle({:ok, v}), do: v
      end
      """

      assert {NoHallucinatedTaskTimeoutErrorStruct, 1} in result.applied_rules
      confirm_fix(result.code, expected)
      assert Credence.RuleCase.compiles?(result.code)
    end
  end
end
