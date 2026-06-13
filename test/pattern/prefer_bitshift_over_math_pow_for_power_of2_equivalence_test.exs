defmodule Credence.Pattern.PreferBitshiftOverMathPowForPowerOf2EquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `trunc(:math.pow(2, x))` → `1 <<< trunc(x)`.
  Both compute 2^x as an integer. `use Bitwise` is needed for `<<<`.
  Input set covers zero, small ints, larger ints, and negative shift.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferBitshiftOverMathPowForPowerOf2

  @before """
  defmodule Solution do
    use Bitwise

    def compute(x) do
      trunc(:math.pow(2, x))
    end
  end
  """

  test "fix preserves behaviour for integer exponents" do
    assert_equivalent_module(@before,
      rule: PreferBitshiftOverMathPowForPowerOf2,
      call: {:compute, 1},
      inputs: [0, 1, 2, 5, 10, -1]
    )
  end
end
