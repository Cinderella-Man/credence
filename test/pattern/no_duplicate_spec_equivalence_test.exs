defmodule Credence.Pattern.NoDuplicateSpecEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic) — no runtime behaviour to compare.

  `@spec` is a compile-time type annotation consumed by tools like Dialyzer.
  It has zero runtime effect; removing a duplicate `@spec` changes no emitted
  code, so no input can witness a difference.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  test "no_duplicate_spec: cosmetic — provably no runtime behaviour to compare" do
    assert :ok =
             mark_equivalence_cosmetic(
               "`@spec` is a compile-time annotation with zero runtime effect; " <>
                 "removing a duplicate changes no emitted code."
             )
  end
end
