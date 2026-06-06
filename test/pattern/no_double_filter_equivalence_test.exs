defmodule Credence.Pattern.NoDoubleFilterEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoDoubleFilter

  # Firing snippets lifted from no_double_filter_check_test.exs:
  #   def split(numbers) do
  #       non_neg = Enum.filter(numbers, &(&1 >= 0))
  #       neg = Enum.filter(numbers, &(&1 < 0))
  #       {non_neg, neg}
  #     end
  #   def split(items) do
  #       big = Enum.filter(items, &(&1 > 10))
  #       small = Enum.filter(items, &(&1 <= 10))
  #       {big, small}
  #     end
  #   def split(items) do
  #       zeros = Enum.filter(items, &(&1 == 0))
  #       nonzeros = Enum.filter(items, &(&1 != 0))
  #       {zeros, nonzeros}
  #     end

  test "no_double_filter: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoDoubleFilter,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
