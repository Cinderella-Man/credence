defmodule Credence.Pattern.NoEagerWithIndexInReduceEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoEagerWithIndexInReduce

  # Firing snippets lifted from no_eager_with_index_in_reduce_check_test.exs:
  #   defmodule BadDirect do
  #       def process(list) do
  #         Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
  #           [{idx, val} | acc]
  #         end)
  #       end
  #     end
  #   defmodule BadPiped do
  #       def process(list) do
  #         list
  #         |> Enum.with_index()
  #         |> Enum.reduce([], fn {val, idx}, acc ->
  #           [{idx, val} | acc]
  #         end)
  #       end
  #     end
  #   defmodule Bad do
  #       def process(list) do
  #         list
  #         |> Enum.filter(&(&1 > 0))
  #         |> Enum.with_index()
  #         |> Enum.reduce([], fn {val, idx}, acc -> [{idx, val} | acc] end)
  #       end
  #     end

  test "no_eager_with_index_in_reduce: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoEagerWithIndexInReduce,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
