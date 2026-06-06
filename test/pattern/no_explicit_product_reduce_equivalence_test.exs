defmodule Credence.Pattern.NoExplicitProductReduceEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoExplicitProductReduce

  # Firing snippets lifted from no_explicit_product_reduce_check_test.exs:
  #   defmodule BadMultiply do
  #       def prod_value(list) do
  #         Enum.reduce(list, 1, fn x, acc ->
  #           x * acc
  #         end)
  #       end
  #     end
  #   defmodule BadMultiplyReversed do
  #       def prod_value(list) do
  #         Enum.reduce(list, 1, fn x, acc ->
  #           acc * x
  #         end)
  #       end
  #     end
  #   defmodule BadCapture do
  #       def prod_value(list) do
  #         Enum.reduce(list, 1, &*/2)
  #       end
  #     end

  test "no_explicit_product_reduce: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoExplicitProductReduce,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
