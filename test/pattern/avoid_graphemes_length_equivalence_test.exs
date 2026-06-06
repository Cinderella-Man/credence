defmodule Credence.Pattern.AvoidGraphemesLengthEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.AvoidGraphemesLength

  # Firing snippets lifted from avoid_graphemes_length_check_test.exs:
  #   str |> String.graphemes() |> length()
  #   String.graphemes(str) |> length()
  #   length(String.graphemes(str))

  test "avoid_graphemes_length: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: AvoidGraphemesLength,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
