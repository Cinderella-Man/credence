defmodule Credence.Pattern.NoRedundantToListEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), enumerable-type dimension.

  `Enum.to_list(items) |> MapSet.new()` → `MapSet.new(items)`. `MapSet.new/1`
  already accepts any enumerable, so dropping the `Enum.to_list/1` is exact —
  including for a non-list enumerable (a range). Input set mixes lists, a range,
  empty, and a value-kind list.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantToList

  test "Enum.to_list(items) |> MapSet.new() → MapSet.new(items) preserves the set" do
    assert_equivalent("Enum.to_list(items) |> MapSet.new()",
      rule: NoRedundantToList,
      vars: [:items],
      inputs: [[], [1, 2, 3], 1..5, [1, 1.0, 2], [:a, :a, :b]]
    )
  end
end
