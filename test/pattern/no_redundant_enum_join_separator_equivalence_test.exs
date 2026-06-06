defmodule Credence.Pattern.NoRedundantEnumJoinSeparatorEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).

  `Enum.join(list, "")` → `Enum.join(list)`. The default separator already is
  `""`, so dropping it is exact. Battery covers strings, integers (stringified),
  empty, and a value-kind list (`1` vs `1.0` both stringify, joined identically).
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantEnumJoinSeparator

  test "Enum.join(list, \"\") → Enum.join(list) preserves the joined string" do
    assert_equivalent(~S|Enum.join(list, "")|,
      rule: NoRedundantEnumJoinSeparator,
      vars: [:list],
      inputs: [[], [1, 2, 3], ["a", "b", "c"], [1, 1.0, 2], [:a, :b]]
    )
  end
end
