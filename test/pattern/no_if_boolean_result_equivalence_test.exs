defmodule Credence.Pattern.NoIfBooleanResultEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `if cond do true else expr end` → `cond or expr` and
  `if cond do expr else false end` → `cond and expr` — safe because the rule
  fires on residuals from `NoCaseTrueFalse` where the condition is boolean.
  Input set drives the condition and the other branch both ways.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoIfBooleanResult

  test "if a do true else b end → a or b preserves the boolean" do
    assert_equivalent(
      """
      if a do
        true
      else
        b
      end
      """,
      rule: NoIfBooleanResult,
      vars: [:a, :b],
      inputs: [{true, true}, {true, false}, {false, true}, {false, false}]
    )
  end

  test "if a do b else false end → a and b preserves the boolean" do
    assert_equivalent(
      """
      if a do
        b
      else
        false
      end
      """,
      rule: NoIfBooleanResult,
      vars: [:a, :b],
      inputs: [{true, true}, {true, false}, {false, true}, {false, false}]
    )
  end
end
