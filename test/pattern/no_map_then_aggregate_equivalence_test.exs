defmodule Credence.Pattern.NoMapThenAggregateEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `coll |> Enum.map(f) |> Enum.sum()` → `Enum.reduce(coll, 0, fn x, acc -> acc + f.(x) end)`.
  Sum aggregates with identity init `0` and applies the mapper to every element,
  so the fusion is exact incl. value-kind.

  Regression note: the rule used to also fire on `Enum.max`/`Enum.min` (selection),
  producing `Enum.reduce/2` whose seed is the *first unmapped* element
  (`[5] |> map(f) |> max()` → `f.(5)` but the fused `reduce/2` gave `5`). Narrowed
  to `:sum` only — selection has no identity to seed a mapped reduce.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapThenAggregate

  test "map(f) |> sum → reduce(0, acc + f) preserves the total incl. value-kind" do
    assert_equivalent(
      """
      numbers |> Enum.map(fn x -> x * 2 end) |> Enum.sum()
      """,
      rule: NoMapThenAggregate,
      vars: [:numbers],
      inputs: [[], [1, 2, 3], [1.0, 2.0], [1, 1.0, 2], [-1, -2, -3], Enum.to_list(1..30)]
    )
  end
end
