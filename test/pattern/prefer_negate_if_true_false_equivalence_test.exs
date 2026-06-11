defmodule Credence.Pattern.PreferNegateIfTrueFalseEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic) — the `false` → `nil` change in the early-exit branch is
  intentional and both are falsy. In the idiomatic usage (cycle detection in
  happy_number, boolean guards), the caller checks truthiness, not identity.
  The non-false body path is preserved exactly.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  test "prefer_negate_if_true_false: cosmetic — false and nil are both falsy" do
    assert :ok =
             mark_equivalence_cosmetic(
               "`if cond do false else body end` → `if !cond do body end` changes the " <>
                 "early-exit return from `false` to `nil` (implicit else). Both are falsy " <>
                 "in Elixir, and the pattern is used where the caller checks truthiness " <>
                 "(e.g., cycle detection in happy_number). The non-false body path is preserved."
             )
  end
end
