defmodule Credence.Pattern.NoMapThenAggregateEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapThenAggregate

  # Firing snippets lifted from no_map_then_aggregate_check_test.exs:
  #   defmodule Bad do
  #       def max_sum(numbers, k) do
  #         numbers
  #         |> Enum.chunk_every(k, 1, :discard)
  #         |> Enum.map(&Enum.sum/1)
  #         |> Enum.max()
  #       end
  #     end
  #   defmodule Bad do
  #       def cheapest(items) do
  #         items
  #         |> Enum.map(& &1.price)
  #         |> Enum.min()
  #       end
  #     end
  #   defmodule Bad do
  #       def total_area(shapes) do
  #         shapes
  #         |> Enum.map(&area/1)
  #         |> Enum.sum()
  #       end
  #     end

  test "no_map_then_aggregate: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoMapThenAggregate,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
