defmodule Credence.Pattern.NoManualCountWithPredicateEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualCountWithPredicate

  # Firing snippets lifted from no_manual_count_with_predicate_check_test.exs:
  #   defmodule Good do
  #       defp count_even([], _n, acc), do: acc
  #       defp count_even([h | t], n, acc) when rem(h, 2) == 0, do: count_even(t, n, acc + 1)
  #       defp count_even([_h | t], n, acc), do: count_even(t, n, acc)
  #     end
  #   defmodule Good do
  #       defp cnt([], _n, acc), do: acc
  #       defp cnt([h | t], n, acc) when h + 1 > n, do: cnt(t, n, acc + 1)
  #       defp cnt([_h | t], n, acc), do: cnt(t, n, acc)
  #     end
  #   defmodule Good do
  #       defp cnt([], _n, acc), do: acc
  #       defp cnt([h | t], n, acc) when hd(h) == n, do: cnt(t, n, acc + 1)
  #       defp cnt([_h | t], n, acc), do: cnt(t, n, acc)
  #     end

  test "no_manual_count_with_predicate: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoManualCountWithPredicate,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
