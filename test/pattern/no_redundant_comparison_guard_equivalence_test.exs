defmodule Credence.Pattern.NoRedundantComparisonGuardEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantComparisonGuard

  # Firing snippets lifted from no_redundant_comparison_guard_check_test.exs:
  #   defmodule Bad do
  #       def sqrt(n) when is_number(n) and n < 0, do: raise(ArgumentError)
  #       def sqrt(0), do: 0.0
  #       def sqrt(n) when is_number(n) and n >= 0, do: :ok
  #     end
  #   defmodule Bad do
  #       def f(n) when is_number(n) and n > 0, do: :positive
  #       def f(n) when is_number(n) and n <= 0, do: :non_positive
  #     end
  #   defmodule Bad do
  #       def classify(n) when is_integer(n) and n <= 5, do: :small
  #       def classify(n) when is_integer(n) and n > 5, do: :big
  #     end

  test "no_redundant_comparison_guard: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoRedundantComparisonGuard,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
