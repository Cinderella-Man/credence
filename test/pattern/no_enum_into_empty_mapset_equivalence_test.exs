defmodule Credence.Pattern.NoEnumIntoEmptyMapsetEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoEnumIntoEmptyMapset

  # Firing snippets lifted from no_enum_into_empty_mapset_check_test.exs:
  #   Enum.into(list, MapSet.new())
  #   Enum.into(list, MapSet.new(), fn x -> x * 2 end)
  #   list |> Enum.into(MapSet.new())

  test "no_enum_into_empty_mapset: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoEnumIntoEmptyMapset,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
