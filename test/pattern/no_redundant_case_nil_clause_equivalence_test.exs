defmodule Credence.Pattern.NoRedundantCaseNilClauseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoRedundantCaseNilClause

  # Firing snippets lifted from no_redundant_case_nil_clause_check_test.exs:
  #   case Map.get(map, key) do
  #       nil ->
  #         default_action()
  #     
  #       prev when prev >= left ->
  #         use_value(prev)
  #     
  #       _prev ->
  #         default_action()
  #     end
  #   case x do
  #       nil -> 0
  #       n when n > 0 -> n
  #       _ -> 0
  #     end
  #   case Map.get(m, k) do
  #       nil ->
  #         a = compute_default()
  #         {a, acc}
  #     
  #       val when val >= threshold ->
  #         a = transform(val)
  #         {a, Map.put(acc, k, val)}
  #     
  #       _val ->
  #         a = compute_default()
  #         {a, acc}
  #     end

  test "no_redundant_case_nil_clause: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoRedundantCaseNilClause,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
