defmodule Credence.Pattern.NoFilterThenFirstEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoFilterThenFirst

  # Firing snippets lifted from no_filter_then_first_check_test.exs:
  #   defmodule M do
  #       def first_even(nums), do: Enum.at(Stream.filter(nums, &even?/1), 0)
  #     end
  #   defmodule M do
  #       def first_even(nums), do: Stream.filter(nums, &even?/1) |> Enum.at(0)
  #     end
  #   defmodule M do
  #       def first_palindrome(nums) do
  #         nums
  #         |> Stream.filter(&palindrome?/1)
  #         |> Enum.at(0)
  #       end
  #     end

  test "no_filter_then_first: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoFilterThenFirst,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
