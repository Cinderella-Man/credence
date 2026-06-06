defmodule Credence.Pattern.NoDeadMapUpdateEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `map |> Map.update(key, 0, & &1) |> Map.drop([key])` → `Map.drop(map, [key])`.
  The identity `Map.update` only touches `key`, which is then dropped, so it is
  dead. Battery covers key present (int/float value) and key absent.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoDeadMapUpdate

  test "dead Map.update before Map.drop → Map.drop preserves the map" do
    assert_equivalent("map |> Map.update(prev, 0, & &1) |> Map.drop([prev])",
      rule: NoDeadMapUpdate,
      vars: [:map, :prev],
      inputs: [
        {%{a: 1}, :a},
        {%{a: 1.0, b: 2}, :a},
        {%{}, :a},
        {%{b: 2}, :a},
        {%{"k" => 5}, "k"}
      ]
    )
  end
end
