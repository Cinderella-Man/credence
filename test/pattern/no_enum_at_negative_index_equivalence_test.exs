defmodule Credence.Pattern.NoEnumAtNegativeIndexEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.at(list, -1)` → `List.last(list)`.
  Proves the harness end-to-end on the simplest expression rewrite.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoEnumAtNegativeIndex

  test "Enum.at(x, -1) → List.last(x) preserves behaviour over term lists" do
    assert_equivalent("Enum.at(list, -1)",
      rule: NoEnumAtNegativeIndex,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
