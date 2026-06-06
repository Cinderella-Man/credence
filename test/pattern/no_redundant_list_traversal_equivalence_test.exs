defmodule Credence.Pattern.NoRedundantListTraversalEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoRedundantListTraversal

  # Firing snippets lifted from no_redundant_list_traversal_check_test.exs:
  #   def run(numbers) do
  #       n = length(numbers)
  #       div(n * (n + 1), 2) - Enum.sum(numbers)
  #     end
  #   def run(numbers) do
  #       count = length(numbers)
  #       doubled_sum = Enum.sum(numbers) * 2
  #       {count, doubled_sum}
  #     end
  #   def run(numbers) do
  #       half_count = div(length(numbers), 2)
  #       sum = Enum.sum(numbers)
  #       {half_count, sum}
  #     end

  test "no_redundant_list_traversal: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoRedundantListTraversal,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
