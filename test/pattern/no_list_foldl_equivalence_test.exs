defmodule Credence.Pattern.NoListFoldlEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `List.foldl(list, acc, fun)` → `Enum.reduce(list, acc, fun)`
  — identical left-to-right order and `fun.(elem, acc)` argument order, so the
  rewrite is a direct, behavior-preserving swap. Verified over lists.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoListFoldl

  test "List.foldl → Enum.reduce preserves accumulation (left-to-right)" do
    assert_equivalent(
      "List.foldl(list, 0, fn x, acc -> acc + x end)",
      rule: NoListFoldl,
      vars: [:list],
      inputs: B.signed_integers()
    )
  end
end
