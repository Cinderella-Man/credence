defmodule Credence.Pattern.NoRedundantDedupBeforeMapsetEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), value-kind dimension.

  `items |> Enum.uniq() |> MapSet.new()` → `MapSet.new(items)`. `MapSet`
  deduplicates by strict `===`, exactly as `Enum.uniq/1` does, so dropping the
  pre-dedup yields the same set — including the `1` vs `1.0` value-kind case
  (both kept distinct either way). Input set includes a value-kind list, empty,
  and duplicates.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoRedundantDedupBeforeMapset

  test "items |> Enum.uniq() |> MapSet.new() → MapSet.new(items) preserves the set" do
    assert_equivalent(
      """
      items |> Enum.uniq() |> MapSet.new()
      """,
      rule: NoRedundantDedupBeforeMapset,
      vars: [:items],
      inputs: B.term_lists()
    )
  end
end
