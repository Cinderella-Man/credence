defmodule Credence.Pattern.NoEnumDropNegativeEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), bounds dimension.
  `Enum.drop(list, -2)` → `Enum.slice(list, 0..-3//1)`. The risk is short/empty
  lists where "drop the last 2" removes more than the list holds; the battery
  covers `[]`, `[1]`, and value-kind lists.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoEnumDropNegative

  test "Enum.drop(list, -2) → Enum.slice preserves behaviour incl. short/empty lists" do
    assert_equivalent("Enum.drop(list, -2)",
      rule: NoEnumDropNegative,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
