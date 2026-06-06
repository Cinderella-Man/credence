defmodule Credence.Pattern.PreferMapPutNewEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferMapPutNew

  # Firing snippets lifted from prefer_map_put_new_check_test.exs:
  #   def run(map, key, val) do
  #       if Map.has_key?(map, key) do
  #         map
  #       else
  #         Map.put(map, key, val)
  #       end
  #     end
  #   def run(list) do
  #       Enum.reduce(list, %{}, fn {k, v}, acc ->
  #         if Map.has_key?(acc, k) do
  #           acc
  #         else
  #           Map.put(acc, k, v)
  #         end
  #       end)
  #     end
  #   def run(map, key, val) do
  #       new_map =
  #         if Map.has_key?(map, key) do
  #           map
  #         else
  #           Map.put(map, key, val)
  #         end
  #     
  #       new_map
  #     end

  test "prefer_map_put_new: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: PreferMapPutNew,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
