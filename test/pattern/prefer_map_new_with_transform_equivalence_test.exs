defmodule Credence.Pattern.PreferMapNewWithTransformEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.map(nums, fn i -> {i, i * i} end) |> Map.new()` →
  `Map.new(nums, fn i -> {i, i * i} end)`. Both produce the same map from the
  enumerable, applying the function to each element and collecting {key, value}
  pairs. Input set covers empty, single element, and multiple elements.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferMapNewWithTransform

  test "Enum.map(nums, fn ...) |> Map.new() → Map.new(nums, fn ...) preserves the map" do
    assert_equivalent(
      """
      Enum.map(nums, fn i -> {i, i * i} end) |> Map.new()
      """,
      rule: PreferMapNewWithTransform,
      vars: [:nums],
      inputs: [[], [1], [1, 2, 3], [5, 4, 3, 2, 1], [10, 20, 30]]
    )
  end
end
