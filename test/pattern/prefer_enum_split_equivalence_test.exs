defmodule Credence.Pattern.PreferEnumSplitEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Adjacent `Enum.take(list, n)` + `Enum.drop(list, n)` on the
  same source merge into `Enum.split(list, n)`. For a non-negative literal `n`,
  `{take(n), drop(n)} == split(n)` for every list incl. shorter-than-n and empty.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferEnumSplit

  @before """
  defmodule Bad do
    def halves(list) do
      first = Enum.take(list, 3)
      rest = Enum.drop(list, 3)
      {first, rest}
    end
  end
  """

  test "take(n) + drop(n) → Enum.split(n) preserves both halves" do
    assert_equivalent_module(@before,
      rule: PreferEnumSplit,
      call: {:halves, 1},
      inputs: [[], [1], [1, 2, 3], [1, 2, 3, 4, 5], Enum.to_list(1..10)]
    )
  end
end
