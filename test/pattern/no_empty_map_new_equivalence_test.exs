defmodule Credence.Pattern.NoEmptyMapNewEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Map.new()` → `%{}`. Both are the empty map; no free vars.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoEmptyMapNew

  test "Map.new() → %{} is the empty map" do
    assert_equivalent("Map.new()",
      rule: NoEmptyMapNew,
      vars: [],
      inputs: [nil],
      allow_few_inputs: true
    )
  end
end
