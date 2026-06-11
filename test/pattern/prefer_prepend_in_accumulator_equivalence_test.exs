defmodule Credence.Pattern.PreferPrependInAccumulatorEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A recursive accumulator function using `List.last(acc)`,
  `acc ++ [next]`, and `Enum.reverse(acc)` is rewritten to pattern-match the
  head, use cons prepend, and remove the now-unnecessary `Enum.reverse/1` —
  same output, O(n) instead of O(n²).
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferPrependInAccumulator

  @before """
  defmodule GroupConsecutive do
    def build_groups(acc, []) do
      [Enum.reverse(acc)]
    end

    def build_groups(acc, [next | rest]) do
      last = List.last(acc)

      if next == last + 1 do
        build_groups(acc ++ [next], rest)
      else
        [Enum.reverse(acc) | build_groups([next], rest)]
      end
    end
  end
  """

  test "List.last + append + reverse → head + prepend preserves grouping" do
    assert_equivalent_module(@before,
      rule: PreferPrependInAccumulator,
      call: {:build_groups, 2},
      inputs: [
        {[1], []},
        {[1], [2, 3, 4]},
        {[1], [2, 3, 5, 6, 7, 9]},
        {[10], [11, 12, 15, 16, 20]},
        {[-5], [-4, -3, -2, 0, 1, 2]},
        {[100], Enum.to_list(101..120)}
      ]
    )
  end
end
