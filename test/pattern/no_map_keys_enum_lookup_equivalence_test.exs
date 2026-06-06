defmodule Credence.Pattern.NoMapKeysEnumLookupEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapKeysEnumLookup

  # Firing snippets lifted from no_map_keys_enum_lookup_check_test.exs:
  #   defmodule Bad do
  #       def check(word_freqs, letter_freqs) do
  #         Map.keys(word_freqs)
  #         |> Enum.all?(fn char ->
  #           Map.get(letter_freqs, char, 0) >= word_freqs[char]
  #         end)
  #       end
  #     end
  #   defmodule Bad do
  #       def transform(counts) do
  #         Map.keys(counts)
  #         |> Enum.map(fn k -> {k, Map.get(counts, k, 0) * 2} end)
  #       end
  #     end
  #   defmodule Bad do
  #       def big_values(data) do
  #         Map.keys(data)
  #         |> Enum.filter(fn k -> Map.fetch!(data, k) > 100 end)
  #       end
  #     end

  test "no_map_keys_enum_lookup: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoMapKeysEnumLookup,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
