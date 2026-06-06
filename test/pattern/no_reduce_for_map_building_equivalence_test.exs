defmodule Credence.Pattern.NoReduceForMapBuildingEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoReduceForMapBuilding

  # Firing snippets lifted from no_reduce_for_map_building_check_test.exs:
  #   defmodule Bad do
  #       def build(list) do
  #         Enum.reduce(list, %{}, fn x, acc ->
  #           Map.put(acc, x, String.length(x))
  #         end)
  #       end
  #     end
  #   defmodule Bad do
  #       def build(list) do
  #         list
  #         |> Enum.reduce(%{}, fn x, acc ->
  #           Map.put(acc, x, x * 2)
  #         end)
  #       end
  #     end
  #   defmodule Bad do
  #       def build(list) do
  #         Enum.reduce(list, MapSet.new(), fn x, acc ->
  #           MapSet.put(acc, x)
  #         end)
  #       end
  #     end

  test "no_reduce_for_map_building: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoReduceForMapBuilding,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
