defmodule Credence.Pattern.PreferEnumSliceEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.PreferEnumSlice

  # Firing snippets lifted from prefer_enum_slice_check_test.exs:
  #   defmodule GoodSlice do
  #       def extract(list, start, len) do
  #         list
  #         |> Enum.slice(start, len)
  #       end
  #     end
  #   defmodule BadPipeline do
  #       def extract(graphemes, best_window_start, best_length) do
  #         graphemes
  #         |> Enum.drop(best_window_start)
  #         |> Enum.take(best_length)
  #       end
  #     end
  #   defmodule DeeplyNested do
  #       def process(list) do
  #         list
  #         |> Enum.map(&(&1 * 2))
  #         |> Enum.filter(&(&1 > 10))
  #         |> Enum.drop(5)
  #         |> Enum.take(3)
  #       end
  #     end

  test "prefer_enum_slice: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: PreferEnumSlice,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
