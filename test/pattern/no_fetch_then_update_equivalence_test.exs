defmodule Credence.Pattern.NoFetchThenUpdateEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoFetchThenUpdate

  # Firing snippets lifted from no_fetch_then_update_check_test.exs:
  #   defmodule BadFetchThenUpdate do
  #       def increment(map, key) do
  #         case Map.fetch(map, key) do
  #           {:ok, val} ->
  #             {val, Map.update!(map, key, &(&1 + 1))}
  #     
  #           :error ->
  #             {0, Map.put(map, key, 1)}
  #         end
  #       end
  #     end
  #   defmodule BadFetchThenUpdate do
  #       def increment(map, key) do
  #         case Map.fetch(map, key) do
  #           {:ok, n} ->
  #             Map.update(map, key, 0, &(&1 + n))
  #     
  #           :error ->
  #             Map.put(map, key, 0)
  #         end
  #       end
  #     end
  #   defmodule LiteralKey do
  #       def bump(map) do
  #         case Map.fetch(map, :count) do
  #           {:ok, n} -> {n, Map.update!(map, :count, &(&1 + 1))}
  #           :error -> {0, Map.put(map, :count, 1)}
  #         end
  #       end
  #     end

  test "no_fetch_then_update: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoFetchThenUpdate,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
