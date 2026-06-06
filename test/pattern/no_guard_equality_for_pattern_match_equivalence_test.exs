defmodule Credence.Pattern.NoGuardEqualityForPatternMatchEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoGuardEqualityForPatternMatch

  # Firing snippets lifted from no_guard_equality_for_pattern_match_check_test.exs:
  #   defmodule GoodMatch do
  #       defp do_count(2, _a, b), do: b
  #       defp do_count(n, a, b), do: do_count(n - 1, b, a + b)
  #     end
  #   defmodule GoodGuard do
  #       def process(n) when is_integer(n) and n > 0 do
  #         n * 2
  #       end
  #     end
  #   defmodule GoodVarGuard do
  #       def compare(a, b) when a == b, do: :equal
  #       def compare(_a, _b), do: :not_equal
  #     end

  test "no_guard_equality_for_pattern_match: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoGuardEqualityForPatternMatch,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
