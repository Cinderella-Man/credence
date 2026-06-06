defmodule Credence.Pattern.NoListDeleteAtWithLengthEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `List.delete_at(tail, length(tail) - 1)` → `List.delete_at(tail, -1)`
  (delete the last element). Equivalent for every list incl. empty and single.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoListDeleteAtWithLength

  test "delete_at(tail, length-1) → delete_at(tail, -1) preserves behaviour incl. empty" do
    assert_equivalent("List.delete_at(tail, length(tail) - 1)",
      rule: NoListDeleteAtWithLength,
      vars: [:tail],
      inputs: B.term_lists()
    )
  end
end
