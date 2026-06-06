defmodule Credence.Pattern.NoFilterThenCountEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoFilterThenCount

  # Firing snippets lifted from no_filter_then_count_check_test.exs:
  #   defmodule Bad do
  #       def count_evens(numbers) do
  #         numbers
  #         |> Enum.filter(fn x -> rem(x, 2) == 0 end)
  #         |> length()
  #       end
  #     end
  #   defmodule Bad do
  #       def count_evens(numbers) do
  #         numbers
  #         |> Enum.filter(fn x -> rem(x, 2) == 0 end)
  #         |> Enum.count()
  #       end
  #     end
  #   defmodule Bad do
  #       def count_positives(items) do
  #         items
  #         |> Enum.filter(&(&1 > 0))
  #         |> length()
  #       end
  #     end

  test "no_filter_then_count: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoFilterThenCount,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
