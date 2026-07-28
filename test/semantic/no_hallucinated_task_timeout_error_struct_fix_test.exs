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

  # ═══════════════════════════════════════════════════════════════════
  # THE WITNESS — this rule was ledgered `:no_fixture` under T1, and the
  # reason was not that nobody had written one. `match?/1` accepted the
  # EXPRESSION-position message while `fix/2` repairs a PATTERN, which
  # emits a different message — so the rule could match or be applicable,
  # never both. Both messages are matched now. docs/22 T5.9.
  # ═══════════════════════════════════════════════════════════════════

  describe "witnesses its own failure mode through the real pipeline" do
    setup do
      source = """
      defmodule TaskTimeoutWitnessCase do
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

      assert Enum.any?(diagnostics, &(&1.message =~ "struct Task.TimeoutError is undefined")),
             "the documented shape is a PATTERN; it never emits the __struct__/1 wording " <>
               "this rule used to key on exclusively"
    end

    test "it is repaired end-to-end through real dispatch", %{source: source} do
      result = Credence.fix(source)

      assert {NoHallucinatedTaskTimeoutErrorStruct, 1} in result.applied_rules
      assert result.code =~ "{:exit, :timeout} ->"
      assert Credence.RuleCase.compiles?(result.code)
    end

    test "the same shape in a function head also witnesses" do
      source = """
      defmodule TaskTimeoutWitnessHead do
        def handle({:exit, {%Task.TimeoutError{}, _stacktrace}}), do: :timeout
        def handle({:ok, v}), do: v
      end
      """

      result = Credence.fix(source)

      assert {NoHallucinatedTaskTimeoutErrorStruct, 1} in result.applied_rules
      assert result.code =~ "def handle({:exit, :timeout})"
      assert Credence.RuleCase.compiles?(result.code)
    end
  end
end
