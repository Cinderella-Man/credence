defmodule Credence.Pattern.NoMapGetSentinelEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapGetSentinel

  # Firing snippets lifted from no_map_get_sentinel_check_test.exs:
  #   def run(char_map, current_char, left_index) do
  #       previous_position = Map.get(char_map, current_char, -1)
  #       if previous_position >= left_index do
  #         previous_position + 1
  #       else
  #         left_index
  #       end
  #     end
  #   def run(map, threshold) do
  #       val = Map.get(map, :key, -1)
  #       if val > threshold, do: val, else: 0
  #     end
  #   def run(map, threshold) do
  #       val = Map.get(map, :key, -1)
  #       if threshold <= val, do: val, else: 0
  #     end

  test "no_map_get_sentinel: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoMapGetSentinel,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
