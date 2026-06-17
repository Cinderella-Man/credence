defmodule Credence.Pattern.NoIdentityFunctionInEnumEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.uniq_by(list, fn x -> x end)` → `Enum.uniq(list)`:
  a `_by` variant with an identity key function is the plain variant. Input set
  covers value-kind and duplicates.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoIdentityFunctionInEnum

  test "Enum.uniq_by(list, fn x -> x end) → Enum.uniq(list) preserves the result" do
    assert_equivalent(
      "Enum.uniq_by(list, fn x -> x end)",
      rule: NoIdentityFunctionInEnum,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
