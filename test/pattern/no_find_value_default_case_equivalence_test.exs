defmodule Credence.Pattern.NoFindValueDefaultCaseEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoFindValueDefaultCase

  # Firing snippets lifted from no_find_value_default_case_check_test.exs:
  #   case Enum.find_value(list, &process/1) do
  #       nil -> :default
  #       val -> val
  #     end
  #   Enum.find_value(list, &process/1) || :default
  #   Enum.find_value(list, &process/1)
  #     |> case do
  #       nil -> :default
  #       val -> val
  #     end

  test "no_find_value_default_case: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoFindValueDefaultCase,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
