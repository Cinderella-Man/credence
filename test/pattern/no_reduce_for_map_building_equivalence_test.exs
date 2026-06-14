defmodule Credence.Pattern.NoReduceForMapBuildingEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `Enum.reduce(list, %{}, fn x, acc -> Map.put(acc, key(x), val(x)) end)` →
  `Map.new(list, fn x -> {key(x), val(x)} end)`. Both build a map by inserting each
  element's key/value in order; on a duplicate key, last-write-wins for both. Inputs
  cover empty, duplicate keys, and a normal list.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoReduceForMapBuilding

  test "reduce(%{}, Map.put) → Map.new preserves the map (incl. duplicate-key last-write-wins)" do
    assert_equivalent(
      "Enum.reduce(list, %{}, fn x, acc -> Map.put(acc, x, String.length(x)) end)",
      rule: NoReduceForMapBuilding,
      vars: [:list],
      inputs: [[], ["a", "bb", "ccc"], ["x", "x"], ["a", "bb", "a"], ["", "z", ""]]
    )
  end
end
