defmodule Credence.Pattern.NoExplicitProductReduceEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.reduce(list, 1, fn x, acc -> acc * x end)` → `Enum.product(list)`.
  Multiplication aggregates (no element-selection), so the value-kind `[1, 1.0]`
  case agrees and the `1` init is the `*` identity. Input set covers empty, ints,
  floats, value-kind, and a zero.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoExplicitProductReduce

  test "reduce(*) → Enum.product preserves the product incl. value-kind" do
    assert_equivalent(
      """
      Enum.reduce(list, 1, fn x, acc -> acc * x end)
      """,
      rule: NoExplicitProductReduce,
      vars: [:list],
      inputs: [[], [1, 2, 3], [1.0, 2.0], [1, 1.0, 2], [0, 5], [-1, -2, 3]]
    )
  end
end
