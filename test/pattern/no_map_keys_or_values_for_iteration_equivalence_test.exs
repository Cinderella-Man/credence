defmodule Credence.Pattern.NoMapKeysOrValuesForIterationEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `Enum.all?(Map.values(m), fn v -> ... end)` → `Enum.all?(m, fn {_k, v} -> ... end)`.
  For order-independent predicates (`all?`/`any?`), iterating the map directly
  over the same values gives the same boolean. Battery covers all-true, a false,
  and empty.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapKeysOrValuesForIteration

  test "Enum.all?(Map.values(m), p) → Enum.all?(m, {_,v} p) preserves the boolean" do
    assert_equivalent("Enum.all?(Map.values(degrees), fn v -> v == 0 end)",
      rule: NoMapKeysOrValuesForIteration,
      vars: [:degrees],
      inputs: [%{}, %{a: 0, b: 0}, %{a: 0, b: 1}, %{x: 0}, Map.new(1..40, fn i -> {i, 0} end)]
    )
  end
end
