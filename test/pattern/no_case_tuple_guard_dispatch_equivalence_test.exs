defmodule Credence.Pattern.NoCaseTupleGuardDispatchEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoCaseTupleGuardDispatch

  # Firing snippets lifted from no_case_tuple_guard_dispatch_check_test.exs:
  #   def run(e1, e2) do
  #       case {e1, e2} do
  #         {e1, e2} when e1 < e2 -> :left
  #         {e1, e2} when e1 > e2 -> :right
  #         _ -> :equal
  #       end
  #     end
  #   def run(e1, e2) do
  #       case {e1, e2} do
  #         {e1, e2} when e1 < e2 -> :left
  #         {e1, e2} when e1 > e2 -> :right
  #         {e1, e2} -> :equal
  #       end
  #     end
  #   def run(a, b, c) do
  #       case {a, b, c} do
  #         {a, b, c} when a < b and b < c -> :ascending
  #         {a, b, c} when a > b and b > c -> :descending
  #         {a, b, c} -> :other
  #       end
  #     end

  test "no_case_tuple_guard_dispatch: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoCaseTupleGuardDispatch,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
