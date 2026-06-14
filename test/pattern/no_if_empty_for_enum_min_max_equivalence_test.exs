defmodule Credence.Pattern.NoIfEmptyForEnumMinMaxEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `if Enum.empty?(x), do: default, else: Enum.min(x)` → `Enum.min(x, fn -> default end)`.
  `Enum.empty?/1` reports emptiness for every enumerable, matching `Enum.min/2`'s
  empty_fallback exactly. Input set leads with the empty list (where the fallback fires).
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoIfEmptyForEnumMinMax

  test "if Enum.empty? default else Enum.min → Enum.min(_, fn -> default end) incl. empty" do
    assert_equivalent(
      "if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)",
      rule: NoIfEmptyForEnumMinMax,
      vars: [:lengths],
      inputs: [[], [3, 1, 2], [5], [1, 1.0, 2], [-3, -1]]
    )
  end

  test "Enum.filter(...) form preserves behaviour, incl. no-match (fallback) and bad input (raise)" do
    # Guard and branch both run the predicate in body position, so `before`
    # (filter twice + empty? check) and `after` (filter once + empty_fallback)
    # agree on every input: the value, the nil fallback when nothing matches,
    # and the ArithmeticError on non-integer elements (e.g. the atom lists in
    # term_lists, where `rem/2` raises identically on both sides).
    assert_equivalent(
      """
      if Enum.empty?(Enum.filter(nums, fn n -> rem(n, 3) == 0 end)),
        do: nil,
        else: Enum.max(Enum.filter(nums, fn n -> rem(n, 3) == 0 end))
      """,
      rule: NoIfEmptyForEnumMinMax,
      vars: [:nums],
      inputs: B.term_lists() ++ B.signed_integers()
    )
  end
end
