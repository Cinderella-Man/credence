defmodule Credence.Pattern.PreferReduceWhileWithHaltValueEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).

  The fix replaces a reduce_while with a boolean flag in the accumulator
  (and post-reduce extraction) with a direct pipe into `case`. Verified
  over lists including empty, single-element, duplicates, and value-kind.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.PreferReduceWhileWithHaltValue

  test "fix preserves behaviour" do
    assert_equivalent(
      """
      {_prefix_sum, _seen_sums, found?} =
        Enum.reduce_while(list, {0, MapSet.new([0]), false}, fn num, {ps, ss, _f} ->
          new_sum = ps + num

          if MapSet.member?(ss, new_sum) do
            {:halt, {new_sum, ss, true}}
          else
            {:cont, {new_sum, MapSet.put(ss, new_sum), false}}
          end
        end)

      found?
      """,
      rule: PreferReduceWhileWithHaltValue,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
