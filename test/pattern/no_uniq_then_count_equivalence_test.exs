defmodule Credence.Pattern.NoUniqThenCountEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoUniqThenCount

  # Firing snippets lifted from no_uniq_then_count_check_test.exs:
  #   defmodule Bad do
  #       def count_unique(items) do
  #         items
  #         |> Enum.uniq()
  #         |> length()
  #       end
  #     end
  #   defmodule Bad do
  #       def count_unique(items) do
  #         items
  #         |> Enum.uniq()
  #         |> Enum.count()
  #       end
  #     end
  #   defmodule Bad do
  #       def count_unique_transformed(words) do
  #         words
  #         |> Enum.map(&transform/1)
  #         |> Enum.uniq()
  #         |> length()
  #       end
  #     end

  test "no_uniq_then_count: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoUniqThenCount,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
