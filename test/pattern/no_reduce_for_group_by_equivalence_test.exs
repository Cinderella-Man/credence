defmodule Credence.Pattern.NoReduceForGroupByEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). The full manual group-by pipeline
  `Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, key(x), [x], &[x | &1]) end) |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)`
  → `Enum.group_by(list, key)`. The rule requires the trailing `Map.new(reverse)`:
  the reduce prepends (`[x | &1]`, reversed groups) and the reverse restores
  insertion order — exactly `Enum.group_by`'s within-group order. Input set covers
  multiple groups, multi-per-group, and empty.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoReduceForGroupBy

  @expr """
  Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, x, [x], &[x | &1]) end)
  |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  """

  test "manual reduce |> Map.new(reverse) → Enum.group_by preserves the grouped map + order" do
    assert_equivalent(@expr,
      rule: NoReduceForGroupBy,
      vars: [:list],
      inputs: [
        [],
        ["apple", "avocado", "banana"],
        ["a", "ab", "ac", "b"],
        ["x", "y", "x", "z", "y"],
        [1, 1.0, 2]
      ]
    )
  end
end
