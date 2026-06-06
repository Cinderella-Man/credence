defmodule Credence.Pattern.NoChunkByIdentityForDedupEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoChunkByIdentityForDedup

  # Firing snippets lifted from no_chunk_by_identity_for_dedup_check_test.exs:
  #   defmodule Example do
  #       def dedup(list) do
  #         list
  #         |> Enum.chunk_by(& &1)
  #         |> Enum.map(&List.first/1)
  #       end
  #     end
  #   defmodule Example do
  #       def dedup(list) do
  #         list
  #         |> Enum.chunk_by(fn x -> x end)
  #         |> Enum.map(&List.first/1)
  #       end
  #     end
  #   defmodule Example do
  #       def compress(list) do
  #         list
  #         |> Enum.chunk_by(& &1)
  #         |> Enum.map_join(&List.first/1)
  #       end
  #     end

  test "no_chunk_by_identity_for_dedup: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoChunkByIdentityForDedup,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
