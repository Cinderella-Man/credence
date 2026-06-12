defmodule Credence.Pattern.PreferConcatOverFlatMapIdentityEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.flat_map(list, fn x -> x end)` → `Enum.concat(list)`:
  an identity flat-map is just concatenation. Input set covers nested lists of
  various depths and contents.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferConcatOverFlatMapIdentity

  test "Enum.flat_map(list, fn x -> x end) → Enum.concat(list) preserves the result" do
    assert_equivalent(
      """
      Enum.flat_map(list, fn x -> x end)
      """,
      rule: PreferConcatOverFlatMapIdentity,
      vars: [:list],
      inputs: [
        [],
        [[1, 2], [3, 4]],
        [[1], [2], [3]],
        [[:a, :b], [:c]],
        [[], [1, 2], [], [3]],
        Enum.map(1..10, fn i -> [i, i * 2] end)
      ]
    )
  end
end
