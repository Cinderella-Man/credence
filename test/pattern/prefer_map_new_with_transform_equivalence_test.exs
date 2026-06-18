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
      "Enum.map(nums, fn i -> {i, i * i} end) |> Map.new()",
      rule: PreferMapNewWithTransform,
      vars: [:nums],
      inputs: [[], [1], [1, 2, 3], [5, 4, 3, 2, 1], [10, 20, 30]]
    )
  end

  # The shape that used to break: an upstream pipeline before the `Enum.map`.
  # `nums |> Enum.filter(...) |> Enum.map(...) |> Map.new()` must fold into
  # `nums |> Enum.filter(...) |> Map.new(...)` — the upstream `Enum.filter`
  # stays in the pipe and the result is identical.
  test "upstream pipeline is preserved and stays equivalent" do
    assert_equivalent(
      "nums |> Enum.filter(fn i -> rem(i, 2) == 0 end) |> Enum.map(fn i -> {i, i * i} end) |> Map.new()",
      rule: PreferMapNewWithTransform,
      vars: [:nums],
      inputs: [[], [1], [1, 2, 3, 4], [5, 4, 3, 2, 1], [2, 4, 6, 8]]
    )
  end
end
