defmodule Credence.Pattern.PreferDescSortOverNegativeTakeEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.PreferDescSortOverNegativeTake

  # Firing snippets lifted from prefer_desc_sort_over_negative_take_check_test.exs:
  #   nums
  #     |> Enum.sort()
  #     |> Enum.take(-3)
  #   Enum.sort(nums) |> Enum.take(-3)
  #   defmodule Example do
  #       def run(nums) do
  #         nums
  #         |> Enum.sort()
  #         |> Enum.take(-5)
  #       end
  #     end

  test "prefer_desc_sort_over_negative_take: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: PreferDescSortOverNegativeTake,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
