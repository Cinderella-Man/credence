defmodule Credence.Pattern.NoRedundantAssignmentEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). A block whose last two statements are `tmp = expr` then
  `tmp` → `expr` (the binding is redundant; the block's value is the last expr).
  Input set drives the computed expression over varied inputs.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantAssignment

  test "tmp = expr; tmp → expr preserves the block value" do
    assert_equivalent("tmp = y * 2 + 1\ntmp",
      rule: NoRedundantAssignment,
      vars: [:y],
      inputs: [0, 1, -3, 100, 2.5]
    )
  end
end
