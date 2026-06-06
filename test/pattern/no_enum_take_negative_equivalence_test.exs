defmodule Credence.Pattern.NoEnumTakeNegativeEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), bounds dimension.
  `Enum.take(list, -2)` → `Enum.slice(list, -2..-1//1)`. The risk is short/empty
  lists where "take the last 2" has fewer than 2 elements; the battery covers
  `[]`, `[1]`, and value-kind lists.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoEnumTakeNegative

  test "Enum.take(list, -2) → Enum.slice preserves behaviour incl. short/empty lists" do
    assert_equivalent("Enum.take(list, -2)",
      rule: NoEnumTakeNegative,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
