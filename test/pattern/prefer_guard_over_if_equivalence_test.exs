defmodule Credence.Pattern.PreferGuardOverIfEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). An `if cond do … else … end` that is a function's whole
  body becomes two guarded clauses. Safe only when `cond` is a non-raising,
  guard-legal test — the rule is narrowed to that core: it does NOT fire when the
  condition contains a call that could raise (verified: `if hd(x) > 0` is left
  alone), so moving it into a guard can't swallow an error or change a truthiness.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferGuardOverIf

  @before """
  defmodule Bad do
    def run(x), do: f(x)
    defp f(x) do
      if x > 0 do
        :pos
      else
        :nonpos
      end
    end
  end
  """

  test "if (guard-legal cond) body → guarded clauses preserve dispatch" do
    assert_equivalent_module(@before,
      rule: PreferGuardOverIf,
      call: {:run, 1},
      inputs: [1, -1, 0, 100, -50]
    )
  end
end
