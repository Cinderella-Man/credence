defmodule Credence.Pattern.NoUnusedUnderscoreAssignmentEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). A block whose non-last `_dead = <pure>` line is removed.
  The dead binding has a pure RHS and the variable is never read, so dropping it
  cannot change the block's value. The input set drives the surviving expression.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoUnusedUnderscoreAssignment

  test "removing a dead literal-RHS underscore binding preserves the block value" do
    assert_equivalent(
      """
      _unused = 1
      n * 2 + 1
      """,
      rule: NoUnusedUnderscoreAssignment,
      vars: [:n],
      inputs: [0, 1, -3, 100, 2.5]
    )
  end

  test "removing a dead bare-var-RHS underscore binding preserves the block value" do
    assert_equivalent(
      """
      _copy = n
      n - 7
      """,
      rule: NoUnusedUnderscoreAssignment,
      vars: [:n],
      inputs: [0, 5, -10, 42, 3.5]
    )
  end
end
