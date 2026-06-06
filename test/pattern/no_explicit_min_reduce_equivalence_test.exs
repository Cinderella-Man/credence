defmodule Credence.Pattern.NoExplicitMinReduceEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoExplicitMinReduce

  # Firing snippets lifted from no_explicit_min_reduce_check_test.exs:
  #   defmodule Goodmin do
  #       def min_value(list) do
  #         Enum.min(list)
  #       end
  #     end
  #   defmodule GoodminBy do
  #       def min_by_value(list) do
  #         Enum.min_by(list, & &1)
  #       end
  #     end
  #   defmodule BadminReduce do
  #       def min_value(list) do
  #         Enum.reduce(list, 0, fn x, acc ->
  #           min(x, acc)
  #         end)
  #       end
  #     end

  test "no_explicit_min_reduce: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoExplicitMinReduce,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
