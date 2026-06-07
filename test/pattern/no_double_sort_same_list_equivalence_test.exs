defmodule Credence.Pattern.NoDoubleSortSameListEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `asc = Enum.sort(arr); desc = Enum.sort(arr, :desc)` rewrites
  the second sort to `Enum.reverse(asc)`. `Enum.sort(arr, :desc) == Enum.reverse(Enum.sort(arr))`
  for the default total order — verified even on value-kind ties (`[1, 1.0]`), since
  equal terms are indistinguishable in the result.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoDoubleSortSameList

  @before """
  defmodule Bad do
    def go(arr) do
      asc = Enum.sort(arr)
      desc = Enum.sort(arr, :desc)
      {asc, desc}
    end
  end
  """

  test "second Enum.sort(:desc) → Enum.reverse(asc) preserves both orderings" do
    assert_equivalent_module(@before,
      rule: NoDoubleSortSameList,
      call: {:go, 1},
      inputs: [[], [1], [3, 1, 2], [1, 1.0, 2], [1.0, 1], Enum.to_list(1..20)]
    )
  end
end
