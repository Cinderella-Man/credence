defmodule Credence.Pattern.NoMapKeysForMembershipEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), value-kind dimension.
  `x in Map.keys(m)` → `Map.has_key?(m, x)`. Both use strict key equality, so the
  `1` vs `1.0` value-kind case agrees (a `1` key is not matched by `1.0`). Input set
  includes value-kind keys, a present key, an absent key, and an atom key.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapKeysForMembership

  test "x in Map.keys(m) → Map.has_key?(m, x) preserves the boolean incl. value-kind keys" do
    assert_equivalent("x in Map.keys(m)",
      rule: NoMapKeysForMembership,
      vars: [:x, :m],
      inputs: [
        {1, %{1 => :a, 2 => :b}},
        {1, %{1.0 => :a}},
        {2, %{1 => :a}},
        {:k, %{k: 1}},
        {"s", %{"s" => 1, "t" => 2}}
      ]
    )
  end
end
