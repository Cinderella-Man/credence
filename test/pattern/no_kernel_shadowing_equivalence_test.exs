defmodule Credence.Pattern.NoKernelShadowingEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). Renames a variable that shadows a Kernel function so the
  call resolves unambiguously: `fn x, max -> max(x, max) end` → `fn x, max_value -> max(x, max_value) end`.
  A pure alpha-rename — behaviour is identical for every input.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoKernelShadowing

  test "renaming the shadowing var preserves the fold result" do
    assert_equivalent(
      """
      Enum.reduce(list, 0, fn x, max -> max(x, max) end)
      """,
      rule: NoKernelShadowing,
      vars: [:list],
      inputs: B.signed_integers()
    )
  end
end
