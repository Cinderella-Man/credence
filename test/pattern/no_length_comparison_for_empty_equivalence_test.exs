defmodule Credence.Pattern.NoLengthComparisonForEmptyEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoLengthComparisonForEmpty

  # Firing snippets lifted from no_length_comparison_for_empty_check_test.exs:
  #   length(l) == 0
  #   0 == length(l)
  #   2 <= length(l)

  test "no_length_comparison_for_empty: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoLengthComparisonForEmpty,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
