defmodule Credence.Pattern.NoListFoldlEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `List.foldl([...], acc, fun)` → `Enum.reduce([...], acc, fun)`
  on a provably-list argument — identical left-to-right fold order and result.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoListFoldl

  test "List.foldl on a literal list ≡ Enum.reduce" do
    assert_equivalent(
      "List.foldl([n, n + 1, n + 2], 0, fn x, acc -> x + acc * 2 end)",
      rule: NoListFoldl,
      vars: [:n],
      inputs: [0, 1, -5, 100, 3]
    )
  end
end
