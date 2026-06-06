defmodule Credence.Pattern.NoIfEmptyForEnumMinMaxEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoIfEmptyForEnumMinMax

  # Firing snippets lifted from no_if_empty_for_enum_min_max_check_test.exs:
  #   defmodule Bad do
  #       def run(lengths) do
  #         if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)
  #       end
  #     end
  #   defmodule Bad do
  #       def run(lengths) do
  #         if Enum.empty?(lengths), do: -1, else: Enum.max(lengths)
  #       end
  #     end
  #   defmodule Bad do
  #       def run(lengths) do
  #         if !Enum.empty?(lengths), do: Enum.min(lengths), else: 0
  #       end
  #     end

  test "no_if_empty_for_enum_min_max: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoIfEmptyForEnumMinMax,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
