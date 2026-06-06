defmodule Credence.Pattern.NoManualMinEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), value-kind dimension.

  `if a <= b, do: a, else: b` → `min(a, b)`. Narrowed to the non-strict form,
  which equals `min/2` exactly. The battery includes equal-value-different-type
  pairs (`{1, 1.0}`, `{1.0, 1}`) — where the strict `<` form would have diverged
  (`min(1, 1.0) == 1`, but `if 1 < 1.0` yields `1.0`).
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualMin

  @pairs [{1, 1.0}, {1.0, 1}, {5, 5}, {2, 3}, {3, 2}, {-1, -1.0}, {0, 0.0}, {-3, 2}]

  test "if a <= b, do: a, else: b → min(a, b) preserves value+type incl. equal-different-type" do
    assert_equivalent("if a <= b, do: a, else: b",
      rule: NoManualMin,
      vars: [:a, :b],
      inputs: @pairs
    )
  end
end
