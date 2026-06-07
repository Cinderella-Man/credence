defmodule Credence.Pattern.InconsistentParamNamesEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic). Renames a positional parameter so the same position uses a
  consistent name across clauses. A parameter is local to its clause, so this is a
  capture-avoiding alpha-rename — the computation each clause performs is unchanged.
  """
  use Credence.RuleCase, async: true
  import Credence.BehaviourEquivalence

  test "inconsistent_param_names: cosmetic — alpha-rename of a clause-local parameter" do
    assert :ok =
             mark_equivalence_cosmetic(
               "Renames a positional parameter for cross-clause consistency — a clause-local " <>
                 "alpha-rename; the value computed by each clause is identical."
             )
  end
end
