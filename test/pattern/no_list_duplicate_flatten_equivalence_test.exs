defmodule Credence.Pattern.NoListDuplicateFlattenEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoListDuplicateFlatten

  # Firing snippets lifted from no_list_duplicate_flatten_check_test.exs:
  #   def tile(list) do
  #       list
  #       |> List.duplicate(3)
  #       |> Enum.concat()
  #     end
  #   def tile(list) do
  #       Enum.concat(List.duplicate(list, 3))
  #     end
  #   Enum.concat(List.duplicate(list, 2))

  test "no_list_duplicate_flatten: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoListDuplicateFlatten,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
