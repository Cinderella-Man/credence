defmodule Credence.Pattern.NoMapKeysForMembershipEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoMapKeysForMembership

  # Firing snippets lifted from no_map_keys_for_membership_check_test.exs:
  #   defmodule TestMod do
  #       def keep_allowed(enum, allowed) do
  #         Enum.filter(enum, &(&1 in Map.keys(allowed)))
  #       end
  #     end
  #   defmodule TestMod do
  #       def lookup(key, map) do
  #         if key in Map.keys(map), do: Map.get(map, key), else: nil
  #       end
  #     end

  test "no_map_keys_for_membership: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoMapKeysForMembership,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
