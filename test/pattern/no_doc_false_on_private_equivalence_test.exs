defmodule Credence.Pattern.NoDocFalseOnPrivateEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic) — no runtime behaviour to compare.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoDocFalseOnPrivate

  # Firing snippets lifted from no_doc_false_on_private_check_test.exs:
  #   (none auto-extracted — see the check test)

  test "no_doc_false_on_private: cosmetic — provably no runtime behaviour to compare" do
    assert :ok = mark_equivalence_cosmetic("`@doc` on a `defp` is discarded by the compiler; removing it changes no emitted code.")
  end
end
