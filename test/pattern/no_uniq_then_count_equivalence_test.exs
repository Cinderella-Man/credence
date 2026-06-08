defmodule Credence.Pattern.NoUniqThenCountEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), value-kind dimension.

  `items |> Enum.uniq() |> length()` → `items |> MapSet.new() |> MapSet.size()`.
  Both `Enum.uniq/1` and `MapSet` dedup by strict `===`, so the `1` vs `1.0`
  value-kind case agrees (both keep `1` and `1.0` as distinct). Input set includes
  a value-kind list, empty, and duplicates.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoUniqThenCount

  test "uniq |> length → MapSet size preserves the count incl. value-kind dedup" do
    assert_equivalent(
      """
      items |> Enum.uniq() |> length()
      """,
      rule: NoUniqThenCount,
      vars: [:items],
      inputs: B.term_lists()
    )
  end
end
