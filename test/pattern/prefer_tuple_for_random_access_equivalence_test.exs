defmodule Credence.Pattern.PreferTupleForRandomAccessEquivalenceTest do
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferTupleForRandomAccess

  test "fix preserves behaviour for pair-counting with difference k" do
    assert_equivalent(
      """
      n = length(numbers)
      pairs = for i <- 0..(n - 2),
                  j <- (i + 1)..(n - 1),
                  abs(Enum.fetch!(numbers, i) - Enum.fetch!(numbers, j)) == k,
                  do: {i, j}
      length(pairs)
      """,
      rule: PreferTupleForRandomAccess,
      vars: [:numbers, :k],
      inputs: [
        {[1, 2, 3], 0},
        {[1, 2, 3], 1},
        {[3, 1, 2, 1, 3, 2], 0},
        {[1, 2, 3, 4, 5], 2},
        {[5, 5, 5], 0}
      ]
    )
  end
end
