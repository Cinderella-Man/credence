defmodule Credence.Pattern.NoLengthGuardToPatternEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoLengthGuardToPattern

  # Firing snippets lifted from no_length_guard_to_pattern_check_test.exs:
  #   defmodule Bad do
  #       def process(list) when length(list) > 0 do
  #         Enum.sum(list)
  #       end
  #     end
  #   defmodule Bad do
  #       defp triplet(list) when length(list) == 3 do
  #         List.to_tuple(list)
  #       end
  #     end
  #   defmodule Bad do
  #       def process(list, x) when length(list) > 0 and is_integer(x) do
  #         :ok
  #       end
  #     end

  test "no_length_guard_to_pattern: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoLengthGuardToPattern,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
