defmodule Credence.Pattern.PreferZipWithOverZipThenCountEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end)`
  → `a |> Enum.zip_with(b, fn x, y -> x != y end) |> Enum.count(& &1)`.

  Both zip the two enumerables element-wise, apply the predicate to each pair,
  and count the truthy results. `Enum.zip_with/3` just avoids the intermediate
  2-tuple list.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferZipWithOverZipThenCount

  test "zip |> count(fn {x, y} -> x != y end) preserves the count" do
    assert_equivalent(
      "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end)",
      rule: PreferZipWithOverZipThenCount,
      vars: [:a, :b],
      inputs: [
        {[], []},
        {[], [1, 2]},
        {[1], [1]},
        {[1, 2, 3], [1, 2, 3]},
        {[1, 2, 3], [4, 5, 6]},
        {[1, 2, 3], [1, 5, 3]},
        {[1, 2], [1, 2, 3, 4]},
        {[nil, false, 1], [1, false, nil]},
        {["a", "b"], ["a", "c"]}
      ]
    )
  end

  test "non-boolean truthy predicate results count the same" do
    assert_equivalent(
      "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x && y end)",
      rule: PreferZipWithOverZipThenCount,
      vars: [:a, :b],
      inputs: [
        {[], []},
        {[1, nil, false, 0], [true, 1, 2, 3]},
        {[:ok, nil], [nil, :ok]},
        {["x"], ["y", "z"]}
      ]
    )
  end
end
