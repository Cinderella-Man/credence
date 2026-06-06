defmodule Credence.Pattern.NoExplicitMaxReduceEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoExplicitMaxReduce

  # Firing snippets lifted from no_explicit_max_reduce_check_test.exs:
  #   defmodule GoodMax do
  #       def max_value(list) do
  #         Enum.max(list)
  #       end
  #     end
  #   defmodule GoodMaxBy do
  #       def max_by_value(list) do
  #         Enum.max_by(list, & &1)
  #       end
  #     end
  #   defmodule BadMaxReduce do
  #       def max_value(list) do
  #         Enum.reduce(list, 0, fn x, acc ->
  #           max(x, acc)
  #         end)
  #       end
  #     end

  test "no_explicit_max_reduce: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoExplicitMaxReduce,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
