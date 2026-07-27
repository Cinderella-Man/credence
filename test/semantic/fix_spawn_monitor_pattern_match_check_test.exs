defmodule Credence.Semantic.FixSpawnMonitorPatternMatchCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixSpawnMonitorPatternMatch

  @real_message "the following pattern will never match:\n\n    {:ok, pid} =\n      spawn_monitor(fn ->\n        try do\n          result = func.(elem)\n          send(self(), {:task_result, ref, {:ok, {idx, result}}})\n        catch\n          kind, reason ->\n            send(self(), {:task_result, ref, {:error, {idx, reason}}})\n            exit({:error, reason})\n        end\n      end)\n\nbecause the right-hand side has type:\n\n    dynamic({reference(), pid()})\n\nwhere \"elem\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:95:64\n    {elem, idx} = item\n\nwhere \"func\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:82:42\n    func\n\nwhere \"idx\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:95:64\n    {elem, idx} = item\n\nwhere \"ref\" was given the type:\n\n    # type: reference()\n    # from: credence_check.ex:97:13\n    ref = make_ref()\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {98, 20}}
    assert FixSpawnMonitorPatternMatch.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixSpawnMonitorPatternMatch.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :warning,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0
    }

    refute FixSpawnMonitorPatternMatch.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {98, 20}}
    assert FixSpawnMonitorPatternMatch.to_issue(diag).rule == :fix_spawn_monitor_pattern_match
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert FixSpawnMonitorPatternMatch.to_issue(diag).meta.line == 42
  end
end
