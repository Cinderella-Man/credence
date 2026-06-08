defmodule Credence.Pattern.NoDoubleFilterEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Two complementary `Enum.filter` passes with predicate `p`
  and its negation collapse to `Enum.split_with(coll, p)`: `{filter(p), filter(not p)}`
  → `split_with(p)`. `split_with` yields `{kept, rejected}` in input order, matching
  the two filters exactly.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoDoubleFilter

  @before """
  defmodule Bad do
    def split(numbers) do
      non_neg = Enum.filter(numbers, &(&1 >= 0))
      neg = Enum.filter(numbers, &(&1 < 0))
      {non_neg, neg}
    end
  end
  """

  test "two complementary filters → Enum.split_with preserves both partitions" do
    assert_equivalent_module(@before,
      rule: NoDoubleFilter,
      call: {:split, 1},
      inputs: [[], [1, -2, 3, -4], [1, 2, 3], [-1, -2], [0, -1, 5, -9, 3]]
    )
  end
end
