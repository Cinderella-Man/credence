defmodule Credence.Pattern.NoDoubleSortSameListEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoDoubleSortSameList

  # Firing snippets lifted from no_double_sort_same_list_check_test.exs:
  #   defmodule GoodSort do
  #       def extremes(arr) do
  #         asc = Enum.sort(arr)
  #         desc = Enum.reverse(asc)
  #         {hd(asc), hd(desc)}
  #       end
  #     end
  #   defmodule SingleSort do
  #       def process(arr) do
  #         Enum.sort(arr)
  #       end
  #     end
  #   defmodule DifferentLists do
  #       def process(a, b) do
  #         sorted_a = Enum.sort(a)
  #         sorted_b = Enum.sort(b, :desc)
  #         {sorted_a, sorted_b}
  #       end
  #     end

  test "no_double_sort_same_list: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoDoubleSortSameList,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
