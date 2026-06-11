defmodule Credence.Pattern.AvoidRebindingParameterEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `def compute(n, k) do k = min(k, n - k); k + 1 end`
  rebinds parameter `k` to `min(k, n - k)`, then uses the rebound value.
  The fix renames to `k_opt` but preserves the same computation.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.AvoidRebindingParameter

  @before """
  defmodule Example do
    def compute(n, k) do
      k = min(k, n - k)
      k + 1
    end
  end
  """

  test "fix preserves behaviour" do
    assert_equivalent_module(@before,
      rule: AvoidRebindingParameter,
      call: {:compute, 2},
      inputs: [{5, 3}, {10, 7}, {1, 0}, {3, 3}, {100, 50}]
    )
  end
end
