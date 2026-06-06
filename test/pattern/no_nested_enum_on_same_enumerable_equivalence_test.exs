defmodule Credence.Pattern.NoNestedEnumOnSameEnumerableEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). An inner `Enum.member?(list, …)` nested inside an outer
  `Enum.map(list, …)` over the same list (O(n²)) is rewritten to hoist a membership
  set. The membership result is identical, so the mapped output is preserved.
  """
  use ExUnit.Case, async: true

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
      inputs: [[], [1, 2, 3], [1, 3, 5], [5], [1, 1, 2]]
    )
  end
end
