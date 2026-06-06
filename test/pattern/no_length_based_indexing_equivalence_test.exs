defmodule Credence.Pattern.NoLengthBasedIndexingEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoLengthBasedIndexing

  # Firing snippets lifted from no_length_based_indexing_check_test.exs:
  #   def run(list) do
  #       n = length(list)
  #       last = Enum.at(list, n - 1)
  #       last
  #     end
  #   def run(sorted) do
  #       n = length(sorted)
  #       largest = Enum.at(sorted, n - 1)
  #       second = Enum.at(sorted, n - 2)
  #       third = Enum.at(sorted, n - 3)
  #       {largest, second, third}
  #     end
  #   def run(list) do
  #       n = Enum.count(list)
  #       last = Enum.at(list, n - 1)
  #       last
  #     end

  test "no_length_based_indexing: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoLengthBasedIndexing,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
