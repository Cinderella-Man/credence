defmodule Credence.Pattern.NoExplicitSumReduceEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoExplicitSumReduce

  # Firing snippets lifted from no_explicit_sum_reduce_check_test.exs:
  #   defmodule GoodSum do
  #       def sum_value(list) do
  #         Enum.sum(list)
  #       end
  #     end
  #   defmodule GoodSumBy do
  #       def sum_by_value(list) do
  #         Enum.sum_by(list, & &1)
  #       end
  #     end
  #   defmodule BadPlus do
  #       def sum_value(list) do
  #         Enum.reduce(list, 0, fn x, acc ->
  #           x + acc
  #         end)
  #       end
  #     end

  test "no_explicit_sum_reduce: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoExplicitSumReduce,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
