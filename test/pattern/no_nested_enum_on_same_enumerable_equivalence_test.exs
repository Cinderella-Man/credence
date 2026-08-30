defmodule Credence.Pattern.NoNestedEnumOnSameEnumerableEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). An inner `Enum.member?(list, …)` nested inside an outer
  `Enum.map(list, …)` over the same list (O(n²)) is rewritten to hoist a membership
  set. The membership result is identical, so the mapped output is preserved.

  Value-kind dimension (C2.2): the rewrite swaps `Enum.member?/2` — which walks
  the list comparing with `===` — for `MapSet.member?/2`, which is a map-key
  lookup. `1` and `1.0` are `==` but neither `===` nor the same map key, so a
  list holding both is the input on which the two membership tests could part
  company. They do not (both say `false` for `2.0` against `[1, 1.0, 2]`), and
  the ties below pin that.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoNestedEnumOnSameEnumerable

  @before """
  defmodule Bad do
    def process(list) do
      Enum.map(list, fn x -> Enum.member?(list, x + 1) end)
    end
  end
  """

  test "nested member? over same list → hoisted membership preserves the mapped result" do
    assert_equivalent_module(@before,
      rule: NoNestedEnumOnSameEnumerable,
      call: {:process, 1},
      inputs: [
        [],
        [1, 2, 3],
        [1, 3, 5],
        [5],
        [1, 1, 2],
        # value-kind ties: `x + 1` lands on `2` for the integer and `2.0` for the
        # float, and neither `Enum.member?` nor `MapSet.member?` accepts the other
        [1, 1.0, 2],
        [1, 2, 2.0],
        [0, 0.0, 1]
      ]
    )
  end
end
