defmodule Credence.Pattern.NoManualMaxEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), value-kind dimension.

  `if a >= b, do: a, else: b` → `max(a, b)`. The rule is narrowed to the
  non-strict form, which equals `max/2` exactly (both keep the first arg on a
  tie). The input set includes equal-value-different-type pairs (`{1, 1.0}`,
  `{1.0, 1}`) — the case where the strict `>` form would have diverged
  (`max(1, 1.0) == 1`, but `if 1 > 1.0` yields `1.0`).
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualMax

  @pairs [{1, 1.0}, {1.0, 1}, {5, 5}, {2, 3}, {3, 2}, {-1, -1.0}, {0, 0.0}, {-3, 2}]

  test "if a >= b, do: a, else: b → max(a, b) preserves value+type incl. equal-different-type" do
    assert_equivalent(
      """
      if a >= b, do: a, else: b
      """,
      rule: NoManualMax,
      vars: [:a, :b],
      inputs: @pairs
    )
  end
end
