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

  # The inner `if b / if c` flattens while the outer `if a` is left intact;
  # the partial rewrite must still select the same branch on every input,
  # including non-boolean truthiness (nil/0 are falsy/truthy respectively).
  @three_level """
  if a do
    1
  else
    if b do
      2
    else
      if c do
        3
      else
        4
      end
    end
  end
  """

  test "three-level nesting: partial flatten preserves branch selection" do
    assert_equivalent(@three_level,
      rule: PreferCondForNestedIf,
      vars: [:a, :b, :c],
      inputs: [
        {true, false, false},
        {false, true, false},
        {false, false, true},
        {false, false, false},
        {nil, nil, :ok}
      ]
    )
  end
end
