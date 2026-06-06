defmodule Credence.Pattern.NoListDuplicateJoinEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoListDuplicateJoin

  # Firing snippets lifted from no_list_duplicate_join_check_test.exs:
  #   def line(n) do
  #       Enum.join(List.duplicate("=", n))
  #     end
  #   def rule do
  #       Enum.join(List.duplicate("-", 80))
  #     end
  #   def line(n) do
  #       "="
  #       |> List.duplicate(n)
  #       |> Enum.join()
  #     end

  test "no_list_duplicate_join: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoListDuplicateJoin,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
