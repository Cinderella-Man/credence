defmodule Credence.Pattern.NoLengthComparisonForEmptyEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `length(l) == 0` → `l == []`.

  Equivalent on `length/1`'s domain — **proper lists** — which is the only place
  the original doesn't crash: `length/1` raises on a non-list or improper list,
  so writing `length(l)` already asserts `l` is a proper list. On that domain
  `length(l) == 0` ⟺ `l == []`. (Outside it the original raises and the rewrite
  returns `false`; that input is already-broken code — not asserted here, the
  input set is proper lists.)
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoLengthComparisonForEmpty

  test "length(l) == 0 → l == [] preserves the boolean over proper lists" do
    assert_equivalent("length(l) == 0",
      rule: NoLengthComparisonForEmpty,
      vars: [:l],
      inputs: B.term_lists()
    )
  end
end
