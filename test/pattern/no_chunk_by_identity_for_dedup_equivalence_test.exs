defmodule Credence.Pattern.NoChunkByIdentityForDedupEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `Enum.chunk_by(list, & &1) |> Enum.map(&List.first/1)` → `Enum.dedup(list)`.
  Both collapse runs of consecutive equal elements (strict `===`), so the
  value-kind `1` vs `1.0` case agrees. Input set covers consecutive duplicates,
  value-kind, and empty.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoChunkByIdentityForDedup

  test "chunk_by(&1) |> map(first) → Enum.dedup preserves the deduped list" do
    assert_equivalent("Enum.chunk_by(list, & &1) |> Enum.map(&List.first/1)",
      rule: NoChunkByIdentityForDedup,
      vars: [:list],
      inputs: [[], [1, 1, 2, 2, 1], [1, 1.0, 1], [1, 2, 3], [:a, :a, :b, :a]]
    )
  end
end
