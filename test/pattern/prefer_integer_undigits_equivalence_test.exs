defmodule Credence.Pattern.PreferIntegerUndigitsEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.reduce(list, 0, fn d, acc -> acc * 10 + d end)` →
  `Integer.undigits(list)`. Both convert a list of digits to an integer. Input
  set covers empty, single-digit, multi-digit, leading zeros, and value-kind.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferIntegerUndigits

  test "reduce(acc * 10 + elem) -> Integer.undigits preserves digit-to-integer" do
    assert_equivalent(
      "Enum.reduce(list, 0, fn digit, acc -> acc * 10 + digit end)",
      rule: PreferIntegerUndigits,
      vars: [:list],
      inputs: [[], [0], [1], [1, 2, 3], [9, 8, 7], [0, 0, 1], [1, 0, 0]]
    )
  end
end
