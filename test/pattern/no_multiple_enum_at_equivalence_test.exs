defmodule Credence.Pattern.NoMultipleEnumAtEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMultipleEnumAt

  # Firing snippets lifted from no_multiple_enum_at_check_test.exs:
  #   defmodule GoodCode do
  #       def extremes(nums) do
  #         sorted = Enum.sort(nums)
  #         [min1, min2 | _] = sorted
  #         [max1, max2 | _] = Enum.reverse(sorted)
  #         {min1, min2, max1, max2}
  #       end
  #     end
  #   defmodule FewCalls do
  #       def first_two(list) do
  #         a = Enum.at(list, 0)
  #         b = Enum.at(list, 1)
  #         {a, b}
  #       end
  #     end
  #   defmodule BadDestructure do
  #       def max_product(nums) do
  #         sorted = Enum.sort(nums)
  #         min1 = Enum.at(sorted, 0)
  #         min2 = Enum.at(sorted, 1)
  #         max1 = Enum.at(sorted, -1)
  #         max2 = Enum.at(sorted, -2)
  #         max(min1 * min2, max1 * max2)
  #       end
  #     end

  test "no_multiple_enum_at: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoMultipleEnumAt,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
