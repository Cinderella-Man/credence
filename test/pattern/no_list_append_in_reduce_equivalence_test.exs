defmodule Credence.Pattern.NoListAppendInReduceEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `Enum.reduce(list, [], fn item, acc -> acc ++ [f(item)] end)` →
  `Enum.reduce(list, [], fn item, acc -> [f(item) | acc] end) |> Enum.reverse()`.
  Prepend-then-reverse yields the same order as repeated append, in O(n) instead
  of O(n²). Input set covers empty and several elements.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoListAppendInReduce

  test "acc ++ [f(item)] reduce → prepend + reverse preserves the order" do
    assert_equivalent(
      "Enum.reduce(list, [], fn item, acc -> acc ++ [item * 2] end)",
      rule: NoListAppendInReduce,
      vars: [:list],
      inputs: [[], [1], [1, 2, 3], [-1, -2, -3], Enum.to_list(1..20)]
    )
  end

  # The reduce result is an operand of `++`, so the fix uses the call form
  # `Enum.reverse(Enum.reduce(...)) ++ [99]`. This proves that output computes the
  # same value as the original `reduce(... acc ++ [x]) ++ [99]`.
  test "reduce in an ++ operator context preserves the value (call form)" do
    assert_equivalent(
      "Enum.reduce(list, [], fn item, acc -> acc ++ [item * 2] end) ++ [99]",
      rule: NoListAppendInReduce,
      vars: [:list],
      inputs: [[], [1], [1, 2, 3], [-1, -2, -3], Enum.to_list(1..20)]
    )
  end
end
