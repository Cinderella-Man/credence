defmodule Credence.Pattern.NoDeadMapUpdateEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoDeadMapUpdate

  # Firing snippets lifted from no_dead_map_update_check_test.exs:
  #   map |> Map.update(key, default(), & &1) |> Map.drop([key])
  #   map |> Map.update(key, seed, & &1) |> Map.drop([key])
  #   map |> Map.update(prev, 0, &(&1 - count)) |> Map.drop([prev])

  test "no_dead_map_update: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoDeadMapUpdate,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
