defmodule Credence.Pattern.NoEnumIntoEmptyMapsetEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.into(list, MapSet.new())` → `MapSet.new(list)`.
  Both build a MapSet from the enumerable (strict `===` dedup), so the value-kind
  `1` vs `1.0` case agrees. Battery covers value-kind, empty, duplicates.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoEnumIntoEmptyMapset

  test "Enum.into(list, MapSet.new()) → MapSet.new(list) builds the same set" do
    assert_equivalent("Enum.into(list, MapSet.new())",
      rule: NoEnumIntoEmptyMapset,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
