defmodule Credence.Semantic.FixSpawnMonitorPatternMatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixSpawnMonitorPatternMatch

  @real_message "the following pattern will never match:\n\n    {:ok, pid} =\n      spawn_monitor(fn ->\n        try do\n          result = func.(elem)\n          send(self(), {:task_result, ref, {:ok, {idx, result}}})\n        catch\n          kind, reason ->\n            send(self(), {:task_result, ref, {:error, {idx, reason}}})\n            exit({:error, reason})\n        end\n      end)\n\nbecause the right-hand side has type:\n\n    dynamic({reference(), pid()})\n\nwhere \"elem\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:95:64\n    {elem, idx} = item\n\nwhere \"func\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:82:42\n    func\n\nwhere \"idx\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:95:64\n    {elem, idx} = item\n\nwhere \"ref\" was given the type:\n\n    # type: reference()\n    # from: credence_check.ex:97:13\n    ref = make_ref()\n"

  defp fix(source, message, line \\ 1) do
    FixSpawnMonitorPatternMatch.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces {:ok, pid} with {_ref, pid} in spawn_monitor pattern" do
    input = ~S"""
    defmodule SpawnMonitorPattern do
      def run do
        {:ok, pid} = spawn_monitor(fn -> :ok end)
        {pid, :done}
      end
    end
    """

    expected = ~S"""
    defmodule SpawnMonitorPattern do
      def run do
        {_ref, pid} = spawn_monitor(fn -> :ok end)
        {pid, :done}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule SpawnMonitorPattern do
      def run do
        {:ok, pid} = spawn_monitor(fn -> :ok end)
        {pid, :done}
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "returns source unchanged when no spawn_monitor pattern present" do
    input = ~S"""
    defmodule CleanExample do
      def run do
        {ref, pid} = spawn_monitor(fn -> :ok end)
        {pid, :done}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
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
