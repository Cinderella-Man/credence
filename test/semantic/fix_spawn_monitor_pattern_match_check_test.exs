defmodule Credence.Semantic.FixSpawnMonitorPatternMatchCheckTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.Semantic.FixSpawnMonitorPatternMatch

  # Verbatim compiler output for `{:ok, pid} = spawn_monitor(fn -> :ok end)`.
  @real_message """
  the following pattern will never match:

      {:ok, pid} = spawn_monitor(fn -> :ok end)

  because the right-hand side has type:

      dynamic({pid(), reference()})
  """

  # Same diagnostic when the pattern is long enough that the compiler prints
  # the assignment across several lines.
  @multiline_message """
  the following pattern will never match:

      {:ok, pid} =
        spawn_monitor(fn ->
          :ok
        end)

  because the right-hand side has type:

      dynamic({pid(), reference()})
  """

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 16}}
    assert FixSpawnMonitorPatternMatch.match?(diag)
  end

  test "dispatches the compiler diagnostic through the semantic pipeline" do
    input =
      """
      defmodule SpawnMonitorPatternMatchSemanticPipelineFixture do
        def run do
          {:ok, pid} = spawn_monitor(fn -> :ok end)
          {pid, :done}
        end
      end
      """
      |> String.trim_trailing()

    expected =
      """
      defmodule SpawnMonitorPatternMatchSemanticPipelineFixture do
        def run do
          {pid, _} = spawn_monitor(fn -> :ok end)
          {pid, :done}
        end
      end
      """
      |> String.trim_trailing()

    assert {:ok, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)

    assert Enum.any?(
             diagnostics,
             &(&1.severity == :warning and &1.message == @real_message and
                 FixSpawnMonitorPatternMatch.match?(&1))
           )

    fixed = Credence.Semantic.fix(input)

    confirm_fix(fixed, expected)

    assert Credence.RuleHelpers.compile_and_capture(fixed) ==
             Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "matches when the compiler prints the pattern across multiple lines" do
    diag = %{severity: :warning, message: @multiline_message, position: {98, 20}}
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

  test "ignores never-match diagnostics that are not about spawn_monitor" do
    message = """
    the following pattern will never match:

        {:ok, value} = {:error, reason}

    because the right-hand side has type:

        dynamic({:error, term()})
    """

    diag = %{severity: :warning, message: message, position: {5, 5}}
    refute FixSpawnMonitorPatternMatch.match?(diag)
  end

  test "ignores qualified spawn_monitor calls the fix does not rewrite" do
    message = """
    the following pattern will never match:

        {:ok, pid} = Kernel.spawn_monitor(fn -> :ok end)

    because the right-hand side has type:

        dynamic({pid(), reference()})
    """

    diag = %{severity: :warning, message: message, position: {3, 16}}
    refute FixSpawnMonitorPatternMatch.match?(diag)
  end

  test "ignores patterns whose second element is not a plain variable" do
    message = """
    the following pattern will never match:

        {:ok, %Task{}} = spawn_monitor(fn -> :ok end)

    because the right-hand side has type:

        dynamic({pid(), reference()})
    """

    diag = %{severity: :warning, message: message, position: {3, 16}}
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
