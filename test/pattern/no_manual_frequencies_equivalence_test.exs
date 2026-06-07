defmodule Credence.Pattern.NoManualFrequenciesEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.reduce(list, %{}, fn item, counts -> Map.update(counts, item, 1, &(&1 + 1)) end)`
  → `Enum.frequencies(list)`. Both count occurrences with strict-`===` keys, so the
  `1` vs `1.0` value-kind case keeps them distinct. (The richer exemplar lives in
  no_manual_frequencies_fix_test.exs; this pins the identity-key case via the harness.)
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoManualFrequencies

  test "manual Map.update reduce → Enum.frequencies preserves the map incl. value-kind keys" do
    assert_equivalent(
      "Enum.reduce(list, %{}, fn item, counts -> Map.update(counts, item, 1, &(&1 + 1)) end)",
      rule: NoManualFrequencies,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
