defmodule Credence.Pattern.FixTaskShutdownBrutalKillFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixTaskShutdownBrutalKill

  test "rewrites :brutal to :brutal_kill" do
    input = "Task.shutdown(task, :brutal)"
    expected = "Task.shutdown(task, :brutal_kill)"
    confirm_fix(fix(FixTaskShutdownBrutalKill, input), expected)
  end
end
