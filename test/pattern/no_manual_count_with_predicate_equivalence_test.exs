defmodule Credence.Pattern.NoManualCountWithPredicateEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A manual `do_count([h|t], …, acc)` recursion that increments
  on a predicate collapses to an `Enum.reduce/3` wrapper. The `is_list`-style domain
  and `==` predicate are preserved, so the count matches — including the value-kind
  case (`1 == 1.0` counts both, in both forms).
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualCountWithPredicate

  @before """
  defmodule Bad do
    def wordcount(list, target), do: do_count(list, target, 0)
    defp do_count([], _t, acc), do: acc
    defp do_count([h | t], target, acc) when h == target, do: do_count(t, target, acc + 1)
    defp do_count([_h | t], target, acc), do: do_count(t, target, acc)
  end
  """

  test "manual predicate-count recursion → Enum.reduce wrapper preserves the count" do
    assert_equivalent_module(@before,
      rule: NoManualCountWithPredicate,
      call: {:wordcount, 2},
      inputs: [{[], 1}, {[1, 2, 1, 3, 1], 1}, {[1, 1.0, 1], 1}, {[:a, :b, :a], :a}, {[2, 3], 1}]
    )
  end

  test "preserves nonnumeric and floating-point accumulators" do
    before = """
    defmodule NonNumericAccumulatorNmcwp do
      def count(list, acc), do: do_count(list, :hit, acc)
      defp do_count([], _target, acc), do: acc
      defp do_count([h | t], target, acc) when h == target, do: do_count(t, target, acc + 1)
      defp do_count([_h | t], target, acc), do: do_count(t, target, acc)
    end
    """

    assert_equivalent_module(before,
      rule: NoManualCountWithPredicate,
      call: {:count, 2},
      inputs: [{[:miss], :seed}, {[:hit], 0.5}, {[:hit, :hit, :hit], 9_007_199_254_740_992.0}]
    )
  end

  test "predicate observes the accumulator as it changes" do
    before = """
    defmodule AccumulatorPredicateNmcwp do
      def count(list, acc), do: do_count(list, acc)
      defp do_count([], acc), do: acc
      defp do_count([h | t], acc) do
        new_acc = if rem(acc, 2) == 0 and h == :hit, do: acc + 1, else: acc
        do_count(t, new_acc)
      end
    end
    """

    assert_equivalent_module(before,
      rule: NoManualCountWithPredicate,
      call: {:count, 2},
      inputs: [{[], 0}, {[:hit], 0}, {[:hit, :hit], 0}]
    )
  end
end
