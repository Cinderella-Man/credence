defmodule Credence.Pattern.NoDefensiveTypeGuardClauseEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). The defensive clause `when not is_integer(n)`
  is dead code for all spec-conformant inputs (integers), so removing it
  preserves behaviour for every integer. Non-integer inputs change from
  returning `false` to crashing — which is the intended "let it crash"
  improvement.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoDefensiveTypeGuardClause

  @before """
  defmodule Solution do
    @spec check_power_of_two(integer()) :: boolean()
    def check_power_of_two(n) when not is_integer(n) do
      false
    end

    def check_power_of_two(n) when n <= 0 do
      false
    end

    def check_power_of_two(n) do
      Bitwise.band(n, n - 1) == 0
    end
  end
  """

  test "removing defensive type guard preserves behaviour for integers" do
    assert_equivalent_module(@before,
      rule: NoDefensiveTypeGuardClause,
      call: {:check_power_of_two, 1},
      inputs: [0, 1, 2, 3, 4, -1, -5, 8, 16, 100]
    )
  end
end
