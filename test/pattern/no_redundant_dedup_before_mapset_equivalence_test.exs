defmodule Credence.Pattern.NoRedundantDedupBeforeMapsetEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoRedundantDedupBeforeMapset

  # Firing snippets lifted from no_redundant_dedup_before_mapset_check_test.exs:
  #   defmodule Example do
  #       def run(items) do
  #         Enum.uniq(items) |> Enum.sort() |> MapSet.new()
  #       end
  #     end
  #   defmodule Example do
  #       def run(items) do
  #         items |> Enum.uniq() |> Enum.sort() |> MapSet.new()
  #       end
  #     end
  #   defmodule Example do
  #       def run(items) do
  #         Enum.dedup(items) |> Enum.sort() |> MapSet.new()
  #       end
  #     end

  test "no_redundant_dedup_before_mapset: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoRedundantDedupBeforeMapset,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
