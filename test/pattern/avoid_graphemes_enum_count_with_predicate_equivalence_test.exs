defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicateEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.AvoidGraphemesEnumCountWithPredicate

  # Firing snippets lifted from avoid_graphemes_enum_count_with_predicate_check_test.exs:
  #   String.graphemes(str) |> Enum.count(&(&1 == "1"))
  #   str |> String.graphemes() |> Enum.count(&(&1 == "1"))
  #   Enum.count(String.graphemes(str), &(&1 == "1"))

  test "avoid_graphemes_enum_count_with_predicate: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: AvoidGraphemesEnumCountWithPredicate,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
