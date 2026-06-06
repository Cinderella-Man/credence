defmodule Credence.Pattern.NoRedundantNegatedGuardEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantNegatedGuard

  # Firing snippets lifted from no_redundant_negated_guard_check_test.exs:
  #   defmodule Bad do
  #       defp compare([v1 | t1], [v2 | t2]) when v1 == v2, do: compare(t1, t2)
  #       defp compare([v1 | _], [v2 |_ ]) when v1 != v2, do: v1
  #     end
  #   defmodule Bad do
  #       defp match(a, b) when a === b, do: :equal
  #       defp match(a, b) when a !== b, do: :not_equal
  #     end
  #   defmodule Bad do
  #       def compare(x, y) when x == y, do: :same
  #       def compare(x, y) when x != y, do: :different
  #     end

  test "no_redundant_negated_guard: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoRedundantNegatedGuard,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
