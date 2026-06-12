defmodule Credence.Pattern.AvoidDuplicateEnumAtEquivalenceTest do
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.AvoidDuplicateEnumAt

  test "fix preserves behaviour" do
    assert_equivalent(
      """
      if Enum.at(nums, mid) > Enum.at(nums, high) do
        :left
      else
        :right
      end
      """,
      rule: AvoidDuplicateEnumAt,
      vars: [:nums, :mid, :high],
      inputs: [
        {[3, 1, 2], 0, 2},
        {[1, 2, 3], 0, 2},
        {[5, 3, 1], 1, 2},
        {[1, 5, 3], 0, 1},
        {[1, 2, 3], 2, 0}
      ]
    )
  end
end
