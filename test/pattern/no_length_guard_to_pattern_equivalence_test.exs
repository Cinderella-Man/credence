defmodule Credence.Pattern.NoLengthGuardToPatternEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `def f(list) when length(list) > 0` → `def f([_ | _] = list)`.
  A proper list has `length > 0` iff it is a cons, so the pattern selects exactly
  the same inputs; the empty list still falls through to the next clause.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoLengthGuardToPattern

  @before """
  defmodule Bad do
    def process(list) when length(list) > 0, do: Enum.sum(list)
    def process(_), do: 0
  end
  """

  test "length(list) > 0 guard → [_|_] pattern preserves dispatch incl. empty" do
    assert_equivalent_module(@before,
      rule: NoLengthGuardToPattern,
      call: {:process, 1},
      inputs: [[], [5], [1, 2, 3], [-1, -2], Enum.to_list(1..20)]
    )
  end
end
