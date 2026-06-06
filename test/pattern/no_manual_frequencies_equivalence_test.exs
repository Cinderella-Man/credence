defmodule Credence.Pattern.NoManualFrequenciesEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoManualFrequencies

  # Firing snippets lifted from no_manual_frequencies_check_test.exs:
  #   defmodule Bad do
  #       def char_freq(string) do
  #         string
  #         |> String.graphemes()
  #         |> Enum.reduce(%{}, fn char, counts ->
  #           Map.update(counts, char, 1, &(&1 + 1))
  #         end)
  #       end
  #     end
  #   Enum.reduce(words, %{}, fn word, acc ->
  #       Map.update(acc, word, 1, &(&1 + 1))
  #     end)
  #   Enum.reduce(words, %{}, fn word, acc ->
  #       Map.update(acc, String.downcase(word), 1, &(&1 + 1))
  #     end)

  test "no_manual_frequencies: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoManualFrequencies,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
