defmodule Credence.Pattern.PreferPrivateHelpersEquivalenceTest do
  @moduledoc """
  The `def` → `defp` conversion is a visibility-only change with no effect on
  runtime behaviour — a function called from within its module produces the same
  result whether it is public or private.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  test "fix is cosmetic — no runtime behaviour change" do
    mark_equivalence_cosmetic(
      "Converting `def` to `defp` is a visibility-only change. " <>
        "The function is only called within its module, so runtime behaviour is identical."
    )
  end
end
