defmodule Credence.Pattern.NoIsPrefixForNonGuardEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic). Renames a boolean-returning function that uses the guard-style
  `is_` prefix (e.g. `is_palindrome`) to the idiomatic trailing-`?` form
  (`palindrome?`) and updates its in-module call sites. A consistent rename —
  behaviour-preserving for the computation; only the function name changes.
  """
  use Credence.RuleCase, async: true
  import Credence.BehaviourEquivalence

  test "no_is_prefix_for_non_guard: cosmetic — `is_foo` → `foo?` rename" do
    assert :ok =
             mark_equivalence_cosmetic(
               "Renames `is_foo` to `foo?` and rewrites in-module call sites — a consistent " <>
                 "rename; the boolean each call computes is unchanged."
             )
  end
end
