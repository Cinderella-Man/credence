defmodule Credence.Pattern.NoRedundantCaseNilClauseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), nil-edge / term-ordering dimension.

  `case x do nil -> 0; n when n > 0 -> n; _ -> 0 end` → the rule drops the
  explicit `nil ->` clause but **adds `not is_nil(n)`** to the intermediate
  guard. That guard is load-bearing: term ordering makes `nil > 0` *true*, so a
  naive deletion would let `nil` fall into `n when n > 0` and return `nil`
  instead of `0`. The input set includes `nil` plus values across types that
  exercise the guard.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantCaseNilClause

  @expr """
  case x do
    nil -> 0
    n when n > 0 -> n
    _ -> 0
  end
  """

  test "dropping the nil clause preserves behaviour (incl. the nil > 0 term-ordering trap)" do
    assert_equivalent(@expr,
      rule: NoRedundantCaseNilClause,
      vars: [:x],
      inputs: [nil, -1, 0, 5, :atom, 3.0, "s"]
    )
  end
end
