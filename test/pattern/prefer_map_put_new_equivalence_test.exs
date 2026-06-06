defmodule Credence.Pattern.PreferMapPutNewEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `if Map.has_key?(map, key), do: map, else: Map.put(map, key, value)` → `Map.put_new(map, key, value)`.
  Equivalent because the rule only fires when `value` is pure — it does NOT fire on
  a side-effecting value (verified) — so `put_new`'s eager evaluation of `value` is
  observationally identical to the if/else's lazy evaluation. Battery covers key
  present (int/float value) and absent.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferMapPutNew

  @expr """
  if Map.has_key?(map, key) do
    map
  else
    Map.put(map, key, value)
  end
  """

  test "if has_key? map else put → Map.put_new preserves the map" do
    assert_equivalent(@expr,
      rule: PreferMapPutNew,
      vars: [:map, :key, :value],
      inputs: [{%{a: 1}, :a, 9}, {%{a: 1.0}, :a, 9}, {%{}, :a, 9}, {%{b: 2}, :a, 9}, {%{"k" => 5}, "k", 7}]
    )
  end
end
