defmodule Credence.Pattern.NoMapPutGetIncrementEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), default/value-kind dimension.

  `Map.put(freqs, char, Map.get(freqs, char, 0) + 1)` → `Map.update(freqs, char, 1, &(&1 + 1))`.
  Present key: both compute `value + 1`; absent key: `Map.get` default `0` + 1 == `Map.update`
  initial `1`. Input set covers absent key, present int, present float value, and non-atom key.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapPutGetIncrement

  test "Map.put(get + 1) → Map.update preserves the map incl. absent/present/float-value keys" do
    assert_equivalent("Map.put(freqs, char, Map.get(freqs, char, 0) + 1)",
      rule: NoMapPutGetIncrement,
      vars: [:freqs, :char],
      inputs: [
        {%{}, :a},
        {%{a: 1}, :a},
        {%{a: 1.0}, :a},
        {%{a: 1}, :b},
        {%{"k" => 5}, "k"}
      ]
    )
  end
end
