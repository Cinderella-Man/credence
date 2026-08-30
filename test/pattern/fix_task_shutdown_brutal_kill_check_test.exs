defmodule Credence.Pattern.FixTaskShutdownBrutalKillCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixTaskShutdownBrutalKill

  test "flags Task.shutdown with :brutal" do
    assert flagged?(FixTaskShutdownBrutalKill, "Task.shutdown(task, :brutal)")
  end

  test "leaves Task.shutdown with :brutal_kill alone" do
    assert clean?(FixTaskShutdownBrutalKill, "Task.shutdown(task, :brutal_kill)")
  end

  test "leaves Task.shutdown with :kill alone" do
    assert clean?(FixTaskShutdownBrutalKill, "Task.shutdown(task, :kill)")
  end

  test "leaves Task.shutdown with timeout alone" do
    assert clean?(FixTaskShutdownBrutalKill, "Task.shutdown(task, 5000)")
  end

  test "flags the piped form" do
    assert flagged?(FixTaskShutdownBrutalKill, "task |> Task.shutdown(:brutal)")
  end

  test "flags the fully qualified form" do
    assert flagged?(FixTaskShutdownBrutalKill, "Elixir.Task.shutdown(task, :brutal)")
  end

  test "leaves a custom module aliased as Task alone" do
    code = """
    alias MyApp.Task, as: Task
    Task.shutdown(task, :brutal)
    """

    assert clean?(FixTaskShutdownBrutalKill, code)
  end

  test "leaves :brutal outside the second-argument slot alone" do
    assert clean?(FixTaskShutdownBrutalKill, "Task.shutdown(:brutal)")
  end
end
