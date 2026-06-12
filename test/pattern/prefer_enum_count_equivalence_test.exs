defmodule Credence.Pattern.PreferEnumCountEquivalenceTest do
  @moduledoc """
  T1 expression. `Enum.reduce(enum, 0, fn x, acc -> if rem(x, 2) == 1, do: acc + 1, else: acc end)` →
  `Enum.count(enum, &(rem(&1, 2) == 1))`.

  The reduce counts odd numbers; the capture-based Enum.count does the same.
  Input set covers empty, all-even, all-odd, mixed, and large lists to verify
  the fix preserves the count on every input.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferEnumCount

  test "counting reduce → Enum.count preserves the count" do
    assert_equivalent(
      """
      Enum.reduce(values, 0, fn count, odd_count ->
        if rem(count, 2) == 1, do: odd_count + 1, else: odd_count
      end)
      """,
      rule: PreferEnumCount,
      vars: [:values],
      inputs: [
        [],
        [1, 2, 3],
        [1, 3, 5],
        [2, 4, 6],
        [0],
        Enum.to_list(1..100)
      ]
    )
  end
end
