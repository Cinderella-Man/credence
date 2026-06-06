defmodule Credence.Pattern.NoMapKeysOrValuesForIterationEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapKeysOrValuesForIteration

  # Firing snippets lifted from no_map_keys_or_values_for_iteration_check_test.exs:
  #   Enum.all?(Map.values(m), fn v -> v == 0 end)
  #   map |> Map.values() |> Enum.count()
  #   Map.keys(map) |> Enum.map(&to_string/1)

  test "no_map_keys_or_values_for_iteration: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoMapKeysOrValuesForIteration,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
