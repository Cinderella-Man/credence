defmodule Credence.Pattern.NoIfEmptyForEnumMinMaxEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `if Enum.empty?(x), do: default, else: Enum.min(x)` → `Enum.min(x, fn -> default end)`.
  `Enum.empty?/1` reports emptiness for every enumerable, matching `Enum.min/2`'s
  empty_fallback exactly. Input set leads with the empty list (where the fallback fires).
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoIfEmptyForEnumMinMax

  test "if Enum.empty? default else Enum.min → Enum.min(_, fn -> default end) incl. empty" do
    assert_equivalent(
      """
      if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)
      """,
      rule: NoIfEmptyForEnumMinMax,
      vars: [:lengths],
      inputs: [[], [3, 1, 2], [5], [1, 1.0, 2], [-3, -1]]
    )
  end
end
