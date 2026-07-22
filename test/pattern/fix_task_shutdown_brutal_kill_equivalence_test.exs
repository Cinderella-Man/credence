defmodule Credence.Pattern.FixTaskShutdownBrutalKillEquivalenceTest do
  use Credence.RuleCase, async: true

  test "fix is a repair — before always crashes" do
    mark_equivalence_repair(
      "Task.shutdown/2 does not accept :brutal — it raises FunctionClauseError " <>
        "on every input. The fix corrects the atom to :brutal_kill."
    )
  end
end
