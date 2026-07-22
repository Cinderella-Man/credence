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

  test "leaves the piped form alone (arity-1 call in AST; fix skips it too)" do
    assert clean?(FixTaskShutdownBrutalKill, "task |> Task.shutdown(:brutal)")
  end

  test "leaves :brutal outside the second-argument slot alone" do
    assert clean?(FixTaskShutdownBrutalKill, "Task.shutdown(:brutal)")
  end
end
