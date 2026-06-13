defmodule Credence.Pattern.PreferCondForNestedIfEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). Nested `if/else` with inner `if` → `cond`.
  The condition evaluation order and branch selection are identical in both forms.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferCondForNestedIf

  @expr """
  if x > 0 do
    "positive"
  else
    if x < 0 do
      "negative"
    else
      "zero"
    end
  end
  """

  test "nested if/else → cond preserves branch selection" do
    assert_equivalent(@expr,
      rule: PreferCondForNestedIf,
      vars: [:x],
      inputs: [1, -1, 0, 100, -100]
    )
  end
end
