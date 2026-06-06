defmodule Credence.Pattern.NoZipThenMapEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoZipThenMap

  # Firing snippets lifted from no_zip_then_map_check_test.exs:
  #   Enum.zip(names, scores)
  #     |> Enum.map(fn {name, score} -> {name, score * 2} end)
  #   Enum.zip(keys, values)
  #     |> Enum.map(fn {k, v} ->
  #       {k, v + 1}
  #     end)
  #   Enum.map(Enum.zip(names, scores), fn {name, score} ->
  #       {name, score * 2}
  #     end)

  test "no_zip_then_map: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoZipThenMap,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
