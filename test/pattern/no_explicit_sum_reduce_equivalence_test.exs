defmodule Credence.Pattern.NoExplicitSumReduceEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.reduce(list, 0, fn x, acc -> acc + x end)` → `Enum.sum(list)`.
  Summation aggregates (no element-selection), so the value-kind `[1, 1.0]` case
  agrees (`2.0` both) and the `0` init is the `+` identity. Input set covers empty,
  ints, floats, value-kind, and negatives.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoExplicitSumReduce

  test "reduce(+) → Enum.sum preserves the total incl. value-kind" do
    assert_equivalent(
      "Enum.reduce(list, 0, fn x, acc -> acc + x end)",
      rule: NoExplicitSumReduce,
      vars: [:list],
      inputs: [[], [1, 2, 3], [1.0, 2.0], [1, 1.0, 2], [-1, -2, -3], Enum.to_list(1..50)]
    )
  end
end
