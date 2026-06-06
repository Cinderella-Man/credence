defmodule Credence.Pattern.NoRedundantNegatedGuardEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). When a clause's guard is the exact negation of the previous
  clause's (`when v1 == v2` then `when v1 != v2`), the second guard is redundant —
  any input reaching it already failed the first — so it can be dropped. Dispatch is
  unchanged because the earlier clause still catches the positive case.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantNegatedGuard

  @before """
  defmodule Bad do
    def cmp(a, b), do: compare(a, b)
    defp compare([v1 | t1], [v2 | t2]) when v1 == v2, do: compare(t1, t2)
    defp compare([v1 | _], [v2 | _]) when v1 != v2, do: v1
  end
  """

  test "dropping the redundant negated guard preserves dispatch" do
    assert_equivalent_module(@before,
      rule: NoRedundantNegatedGuard,
      call: {:cmp, 2},
      inputs: [{[1, 2], [1, 3]}, {[1], [1]}, {[5], [9]}, {[1, 2, 3], [1, 2, 3]}, {[1, 9], [1, 9]}]
    )
  end
end
