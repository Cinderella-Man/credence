defmodule Credence.Pattern.NoZipThenMapEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `Enum.zip(a, b) |> Enum.map(fn {x, y} -> x + y end)` → `Enum.zip_with(a, b, fn x, y -> x + y end)`.
  Both pair-and-map in order, stopping at the shorter list. Input set covers equal,
  unequal, and empty lengths.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoZipThenMap

  test "zip |> map → zip_with preserves the paired result incl. unequal lengths" do
    assert_equivalent(
      "Enum.zip(a, b) |> Enum.map(fn {x, y} -> x + y end)",
      rule: NoZipThenMap,
      vars: [:a, :b],
      inputs: [
        {[1, 2, 3], [4, 5, 6]},
        {[1, 2], [9]},
        {[], []},
        {[1], [2, 3, 4]},
        {[1, 1.0], [2, 2]}
      ]
    )
  end
end
