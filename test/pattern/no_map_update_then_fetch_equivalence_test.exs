defmodule Credence.Pattern.NoMapUpdateThenFetchEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapUpdateThenFetch

  # Firing snippets lifted from no_map_update_then_fetch_check_test.exs:
  #   defmodule GoodUpdate do
  #       def increment(map, key) do
  #         count = Map.get(map, key, 0) + 1
  #         new_map = Map.put(map, key, count)
  #         {new_map, count}
  #       end
  #     end
  #   defmodule SafeFetch do
  #       def get_value(map, key) do
  #         Map.fetch!(map, key)
  #       end
  #     end
  #   defmodule BadDoubleTraversal do
  #       def increment(map, key) do
  #         map = Map.update(map, key, 1, &(&1 + 1))
  #         val = Map.fetch!(map, key)
  #         {map, val}
  #       end
  #     end

  test "no_map_update_then_fetch: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoMapUpdateThenFetch,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
