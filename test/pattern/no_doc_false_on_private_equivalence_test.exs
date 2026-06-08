defmodule Credence.Pattern.NoDocFalseOnPrivateEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic) — no runtime behaviour to compare.

  The rule deletes a `@doc false` that sits above a `defp`. The compiler
  discards `@doc` on a private function entirely, so removing it changes no
  emitted code; no input can witness a difference.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  test "no_doc_false_on_private: cosmetic — provably no runtime behaviour to compare" do
    assert :ok =
             mark_equivalence_cosmetic(
               "`@doc` on a `defp` is discarded by the compiler; removing it changes no emitted code."
             )
  end
end
