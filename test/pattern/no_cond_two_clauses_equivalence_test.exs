defmodule Credence.Pattern.NoCondTwoClausesEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoCondTwoClauses

  # Firing snippets lifted from no_cond_two_clauses_check_test.exs:
  #   def run(x, target) do
  #       cond do
  #         x <= target -> :left
  #         x > target -> :right
  #       end
  #     end
  #   def run(x, y) do
  #       cond do
  #         x < y -> :less
  #         x >= y -> :not_less
  #       end
  #     end
  #   def run(x, y) do
  #       cond do
  #         x == y -> :equal
  #         x != y -> :not_equal
  #       end
  #     end

  test "no_cond_two_clauses: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoCondTwoClauses,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
