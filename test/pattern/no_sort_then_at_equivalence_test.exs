defmodule Credence.Pattern.NoSortThenAtEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoSortThenAt

  # Firing snippets lifted from no_sort_then_at_check_test.exs:
  #   defmodule M do
  #       def largest(nums), do: Enum.sort(nums, fn a, b -> a > b end) |> Enum.at(0)
  #     end
  #   defmodule M do
  #       def largest(nums), do: Enum.sort(nums, fn a, b -> a < b end) |> Enum.at(-1)
  #     end
  #   defmodule M do
  #       def largest(nums), do: Enum.sort(nums, fn a, b -> b < a end) |> Enum.at(0)
  #     end

  test "no_sort_then_at: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoSortThenAt,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
