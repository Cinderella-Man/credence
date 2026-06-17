defmodule Credence.Pattern.PreferNegateIfTrueFalseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — the rewrite negates the condition and swaps branches,
  preserving the explicit `false` in the else branch. The return type is
  identical for every input: both branches produce the same values.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  test "prefer_negate_if_true_false: exact equivalence — branches are swapped, not dropped" do
    # A non-boolean else body keeps this in this rule's unique territory
    # (no_if_true_false only collapses boolean-else ifs), and exercises that the
    # branches are swapped rather than collapsed to a bare boolean.
    assert :ok =
             assert_equivalent(
               """
               if rem(n, 3) == 0 do
                 false
               else
                 n * 2
               end
               """,
               rule: Credence.Pattern.PreferNegateIfTrueFalse,
               vars: [:n],
               inputs: [1, 3, 5, 7, 15, 30]
             )
  end
end
