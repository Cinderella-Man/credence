defmodule Credence.Pattern.PreferEnumSliceEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), bounds dimension.
  `Enum.drop(list, s) |> Enum.take(l)` → `Enum.slice(list, s, l)` — equivalent
  only for non-negative `s`, `l`, which is exactly what the (now-narrowed) rule
  fires on. Input set covers in-range, past-the-end, single, and empty lists.

  Regression note: the rule used to fire on negative drop/take and on variable
  amounts (which could be negative) — both diverge from `Enum.slice/3`
  (`drop(-1) |> take(2)` vs `slice(-1, 2)`; `take(-2)` vs `slice(_, -2)` which
  raises). Narrowed to non-negative integer literals only.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferEnumSlice

  test "Enum.drop(list, 1) |> Enum.take(2) → Enum.slice(list, 1, 2) over varied lengths" do
    assert_equivalent("Enum.drop(list, 1) |> Enum.take(2)",
      rule: PreferEnumSlice,
      vars: [:list],
      inputs: [[], [1], [1, 2], [1, 2, 3, 4, 5], [:a, :b, :c], [1, 1.0, 2, 3]]
    )
  end

  test "Enum.drop(list, 0) |> Enum.take(3) (start 0) → Enum.slice(list, 0, 3)" do
    assert_equivalent("Enum.drop(list, 0) |> Enum.take(3)",
      rule: PreferEnumSlice,
      vars: [:list],
      inputs: [[], [1], [1, 2, 3, 4, 5]]
    )
  end
end
