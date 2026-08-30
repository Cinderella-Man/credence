defmodule Credence.ConcurrentAnalysisTest do
  @moduledoc """
  Two files that define the same module name must analyse correctly in parallel.

  ## The defect this pins

  Compiling is a GLOBAL side effect: `Code.compile_string/2` loads modules into
  the code server and `RuleHelpers.safe_cleanup_modules/1` deletes them again.
  Two concurrent analyses of DIFFERENT files that happen to define the SAME
  module name therefore raced — one deleted the module the other was still
  working with.

  Measured before the fix, on two files each containing one unused variable:

      same module name        30 of 30 runs divergent
      different module names   0 of 30 runs divergent

  and the divergence was a false **negative** — `[]` where `[:unused_variable]`
  was expected. That is the worst direction for a linter: it does not fail
  loudly, it quietly approves broken code.

  It surfaced as a test flake — `pipeline_witness` reporting a healthy rule as
  dead — but the flake was the symptom, not the bug. Anything that analyses
  files in parallel hits it, and `defmodule Example` is not a rare name in the
  generated code this tool exists for.

  The repair is a lock keyed on the module names in the source, so files
  defining different modules still compile concurrently.
  """
  use ExUnit.Case, async: false

  @same_a """
  defmodule ConcurrentSameName do
    def f(x) do
      y = x + 1
      :ok
    end
  end
  """

  @same_b """
  defmodule ConcurrentSameName do
    def g(z) do
      w = z * 2
      :ok
    end
  end
  """

  @different """
  defmodule ConcurrentOtherName do
    def g(z) do
      w = z * 2
      :ok
    end
  end
  """

  defp rules_of(source) do
    source |> Credence.analyze(source: source) |> Map.fetch!(:issues) |> Enum.map(& &1.rule)
  end

  defp concurrently(a, b, times) do
    for _ <- 1..times do
      task_a = Task.async(fn -> rules_of(a) end)
      task_b = Task.async(fn -> rules_of(b) end)
      {Task.await(task_a, 60_000), Task.await(task_b, 60_000)}
    end
  end

  test "the sequential answers are what the concurrent ones must reproduce" do
    assert rules_of(@same_a) == [:unused_variable]
    assert rules_of(@same_b) == [:unused_variable]
    assert rules_of(@different) == [:unused_variable]
  end

  test "two files defining the SAME module analyse correctly in parallel" do
    runs = concurrently(@same_a, @same_b, 20)

    divergent = Enum.reject(runs, &(&1 == {[:unused_variable], [:unused_variable]}))

    assert divergent == [],
           """
           #{length(divergent)} of #{length(runs)} concurrent runs returned the wrong
           issues for files sharing a module name. Before the compile lock this
           was 30 of 30, and the wrong answer was `[]` — a silent false negative.

           Sample: #{inspect(Enum.take(divergent, 3))}
           """
  end

  test "two files defining DIFFERENT modules compile concurrently" do
    coordinator = :credence_different_module_lock_test
    Process.register(self(), coordinator)

    source = fn label, module ->
      "send(#{inspect(coordinator)}, {:entered, #{inspect(label)}, self()})\n" <>
        "receive do :continue -> :ok end\n" <> "defmodule #{module} do end"
    end

    tasks =
      Enum.map(
        [source.(:a, "ConcurrentDifferentA"), source.(:b, "ConcurrentDifferentB")],
        fn input ->
          Task.async(fn -> Credence.RuleHelpers.compile_and_capture(input) end)
        end
      )

    assert_receive {:entered, first_label, first_pid}, 1_000
    assert_receive {:entered, second_label, second_pid}, 1_000
    assert MapSet.new([first_label, second_label]) == MapSet.new([:a, :b])
    send(first_pid, :continue)
    send(second_pid, :continue)

    assert Enum.map(tasks, &Task.await(&1, 5_000)) == [{:ok, []}, {:ok, []}]
  end

  test "overlapping module sets cannot compile concurrently" do
    coordinator = :credence_overlapping_module_lock_test
    Process.register(self(), coordinator)

    source = fn label, modules ->
      "send(#{inspect(coordinator)}, {:entered, #{inspect(label)}, self()})\n" <>
        "receive do :continue -> :ok end\n" <> modules
    end

    both =
      source.(:both, "defmodule ConcurrentOverlapA do end\ndefmodule ConcurrentOverlapB do end")

    one = source.(:one, "defmodule ConcurrentOverlapA do end")

    tasks =
      Enum.map([both, one], fn input ->
        Task.async(fn -> Credence.RuleHelpers.compile_and_capture(input) end)
      end)

    assert_receive {:entered, _label, first_pid}, 1_000
    refute_receive {:entered, _label, _pid}, 100
    send(first_pid, :continue)

    assert_receive {:entered, _label, second_pid}, 1_000
    send(second_pid, :continue)

    assert Enum.map(tasks, &Task.await(&1, 5_000)) == [{:ok, []}, {:ok, []}]
  end
end
