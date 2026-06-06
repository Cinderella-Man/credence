defmodule Credence.Pattern.NoGroupByForFrequenciesEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoGroupByForFrequencies

  # Firing snippets lifted from no_group_by_for_frequencies_check_test.exs:
  #   defmodule M do
  #       def freq(words) do
  #         words
  #         |> Enum.group_by(&String.downcase/1)
  #         |> Map.new(fn {key, group} -> {key, length(group)} end)
  #       end
  #     end
  #   defmodule M do
  #       def freq(words) do
  #         Map.new(Enum.group_by(words, &String.downcase/1), fn {key, group} -> {key, length(group)} end)
  #       end
  #     end
  #   defmodule M do
  #       def freq(list) do
  #         list
  #         |> Enum.group_by(& &1)
  #         |> Map.new(fn {k, g} -> {k, Enum.count(g)} end)
  #       end
  #     end

  test "no_group_by_for_frequencies: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoGroupByForFrequencies,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
