defmodule Credence.Pattern.NoListDuplicateFlattenEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `Enum.concat(List.duplicate(list, 3))` → `Enum.flat_map(1..3, fn _ -> list end)`.
  Both produce `list` repeated 3 times concatenated. Input set covers empty,
  value-kind, and a normal list.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoListDuplicateFlatten

  test "Enum.concat(List.duplicate(list, 3)) → flat_map preserves the concatenation" do
    assert_equivalent("Enum.concat(List.duplicate(list, 3))",
      rule: NoListDuplicateFlatten,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
