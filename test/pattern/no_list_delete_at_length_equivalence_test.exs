defmodule Credence.Pattern.NoListDeleteAtLengthEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), bounds dimension.
  `List.delete_at(list, length(list) - 1)` → `List.delete_at(list, -1)` (delete
  the last element). Equivalent for every list — including `[]` (both return
  `[]`) and single-element lists. Input set covers empty, single, and value-kind.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoListDeleteAtLength

  test "delete_at(list, length-1) → delete_at(list, -1) preserves behaviour incl. empty" do
    assert_equivalent("List.delete_at(list, length(list) - 1)",
      rule: NoListDeleteAtLength,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
