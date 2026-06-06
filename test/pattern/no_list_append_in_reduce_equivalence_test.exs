defmodule Credence.Pattern.NoListAppendInReduceEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoListAppendInReduce

  # Firing snippets lifted from no_list_append_in_reduce_check_test.exs:
  #   defmodule Bad do
  #       def process(list) do
  #         Enum.reduce(list, [], fn item, acc ->
  #           acc ++ [item * 2]
  #         end)
  #       end
  #     end
  #   defmodule Bad do
  #       def process(list) do
  #         list |> Enum.reduce([], fn item, acc ->
  #           acc ++ [item]
  #         end)
  #       end
  #     end
  #   defmodule Bad do
  #       def process(list) do
  #         Enum.reduce(list, [], fn item, acc ->
  #           processed = item * 2
  #           acc ++ [processed]
  #         end)
  #       end
  #     end

  test "no_list_append_in_reduce: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoListAppendInReduce,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
