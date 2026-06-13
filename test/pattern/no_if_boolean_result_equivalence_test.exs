defmodule Credence.Pattern.NoIfBooleanResultEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `if cond do true else expr end` → `cond or expr` and
  `if cond do expr else false end` → `cond and expr` — safe only because the
  rule fires solely on a *provably-boolean* condition (here a comparison), so
  feeding it into `or`/`and` cannot raise BadBooleanError. Input set drives the
  condition and the other branch both ways.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoIfBooleanResult

  test "if a == true do true else b end → (a == true) or b preserves the boolean" do
    assert_equivalent(
      """
      if a == true do
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

  test "if a == true do b else false end → (a == true) and b preserves the boolean" do
    assert_equivalent(
      """
      if a == true do
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
