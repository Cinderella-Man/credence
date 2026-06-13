defmodule Credence.Pattern.PreferPatternMatchOverConditionalInRecursiveCountEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Recursive count via if-conditional splits into
  pattern-matching clauses. The before and after must return the same count
  for every input: empty lists, matching/non-matching elements, multiple
  matches, and value-kind traps (1 vs 1.0).
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferPatternMatchOverConditionalInRecursiveCount

  @before """
  defmodule CountUntil do
    def count_until([], _target, _stop), do: 0
    def count_until([stop | _rest], _target, stop), do: 0
    def count_until([head | tail], target, stop) do
      count = if head == target, do: 1, else: 0
      count + count_until(tail, target, stop)
    end
  end
  """

  test "if-count → pattern-match clauses preserves counting behaviour" do
    assert_equivalent_module(@before,
      rule: PreferPatternMatchOverConditionalInRecursiveCount,
      call: {:count_until, 3},
      inputs: [
        {[], 1, 99},
        {[1], 1, 99},
        {[1, 2, 3], 1, 99},
        {[1, 1, 1], 1, 99},
        {[2, 3, 4], 1, 99},
        {[1, 2, 1, 3, 1], 1, 99},
        {[1, 2, 3, 1], 1, 2},
        # value-kind trap: 1 vs 1.0
        {[1, 1.0, 2], 1, 99}
      ]
    )
  end
end
