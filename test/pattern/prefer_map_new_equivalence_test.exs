defmodule Credence.Pattern.PreferMapNewEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.zip(key_list, value_list) |> Enum.into(%{})` →
  `Enum.zip(key_list, value_list) |> Map.new()`.  Both build a map by zipping
  two lists into key-value pairs; `Enum.zip` truncates to the shorter list, so
  different-length inputs are safe.  Inputs cover empty, single, same-length,
  different-length, duplicate keys (last-write-wins), and value-kind traps.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferMapNew

  test "Enum.zip(k, v) |> Enum.into(%{}) → Enum.zip(k, v) |> Map.new() preserves the map" do
    assert_equivalent(
      """
      Enum.zip(key_list, value_list) |> Enum.into(%{})
      """,
      rule: PreferMapNew,
      vars: [:key_list, :value_list],
      inputs: [
        # both empty
        {[], []},
        # single pair
        {[:a], [1]},
        # same length
        {[:a, :b, :c], [1, 2, 3]},
        # different lengths (zip truncates)
        {[:a, :b, :c, :d], [1, 2]},
        {[:x], [1, 2, 3]},
        # duplicate keys — last-write-wins for both
        {[:a, :b, :a, :c], [1, 2, 3, 4]},
        # value-kind trap: 1 and 1.0 are distinct as map keys
        {[1, 1.0, 1], [:a, :b, :c]},
        # nil / false keys
        {[nil, false, nil], [1, 2, 3]},
        # large
        {Enum.to_list(1..200), Enum.to_list(101..300)}
      ]
    )
  end
end
