defmodule Credence.Pattern.NoEmptyMapNewEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoEmptyMapNew

  # Firing snippets lifted from no_empty_map_new_check_test.exs:
  #   Map.new(list, fn x -> {x, true} end)
  #   Map.new(pairs)
  #   list |> Map.new()

  test "no_empty_map_new: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoEmptyMapNew,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
