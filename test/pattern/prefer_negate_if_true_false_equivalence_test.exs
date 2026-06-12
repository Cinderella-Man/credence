defmodule Credence.Pattern.PreferNegateIfTrueFalseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — the rewrite negates the condition and swaps branches,
  preserving the explicit `false` in the else branch. The return type is
  identical for every input: both branches produce the same values.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  test "prefer_negate_if_true_false: exact equivalence — branches are swapped, not dropped" do
    assert :ok =
             assert_equivalent(
               """
               if rem(n, 3) == 0 do
                 false
               else
                 rem(n, 5) == 0
               end
               """,
               rule: Credence.Pattern.PreferNegateIfTrueFalse,
               vars: [:n],
               inputs: [1, 3, 5, 7, 15, 30]
             )
  end
end
