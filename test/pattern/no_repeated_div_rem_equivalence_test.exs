defmodule Credence.Pattern.NoRepeatedDivRemEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Two identical `rem(x, 2)` (or `div`) computations in the
  same scope collapse to a single binding reused. `rem`/`div` are pure, so the
  deduplicated value is identical.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRepeatedDivRem

  @before """
  defmodule Bad do
    def check(x) do
      a = rem(x, 2)
      b = rem(x, 2)
      {a, b}
    end
  end
  """

  test "deduplicated rem/div preserves the computed values" do
    assert_equivalent_module(@before,
      rule: NoRepeatedDivRem,
      call: {:check, 1},
      inputs: [5, 4, 0, -3, 100]
    )
  end
end
