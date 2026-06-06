defmodule Credence.Pattern.NoMapPutGetIncrementEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoMapPutGetIncrement

  # Firing snippets lifted from no_map_put_get_increment_check_test.exs:
  #   defmodule Freq do
  #       def count(char, freqs) do
  #         Map.put(freqs, char, Map.get(freqs, char, 0) + 1)
  #       end
  #     end
  #   defmodule Solution do
  #       defp count_frequencies(<<>>), do: %{}
  #       defp count_frequencies(<<char, rest::binary>>) do
  #         freqs = count_frequencies(rest)
  #         Map.put(freqs, char, Map.get(freqs, char, 0) + 1)
  #       end
  #     end
  #   freqs |> Map.put(key, Map.get(freqs, key, 0) + 1)

  test "no_map_put_get_increment: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoMapPutGetIncrement,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
