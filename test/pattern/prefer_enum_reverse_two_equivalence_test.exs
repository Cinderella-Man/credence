defmodule Credence.Pattern.PreferEnumReverseTwoEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.reverse(acc) ++ tail` → `Enum.reverse(acc, tail)`.
  `Enum.reverse/2` is defined as `reverse(acc) ++ tail`, so it is exact. Input set
  covers empty/non-empty acc and tail, and a value-kind list.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferEnumReverseTwo

  test "Enum.reverse(acc) ++ tail → Enum.reverse(acc, tail) preserves the list" do
    assert_equivalent("Enum.reverse(acc) ++ tail",
      rule: PreferEnumReverseTwo,
      vars: [:acc, :tail],
      inputs: [{[1, 2], [3, 4]}, {[], [1]}, {[1], []}, {[], []}, {[1, 1.0], [2]}]
    )
  end
end
