defmodule Credence.Pattern.NoTautologicalIfEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `if cond, do: v, else: v` (both branches identical) → `v`.

  Dropping the condition is safe only when evaluating it has no observable
  effect — the rule already narrows to conditions that are pure and total (it
  does NOT fire when the condition contains a function call like `hd(x)` that
  could raise). The input set drives the (total) condition both ways; the value is
  the same regardless, as the fix asserts.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoTautologicalIf

  test "if (total cond), do: v, else: v → v preserves the value" do
    assert_equivalent(
      """
      if x > 0, do: :v, else: :v
      """,
      rule: NoTautologicalIf,
      vars: [:x],
      inputs: [1, -1, 0, :atom, "s"],
      # Both branches are `:v`, so the original returns `:v` for every input — the
      # output is constant by design, not a sign of weak inputs.
      allow_constant_output: true
    )
  end
end
