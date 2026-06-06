defmodule Credence.Pattern.NoCaseTupleGuardDispatchEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `case {e1, e2} do {e1, e2} when e1 < e2 -> ...; ... end`
  becomes guarded function heads. The clause order, tuple patterns, and guards are
  preserved, so dispatch is identical (including the value-kind `{1, 1.0}` case).
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoCaseTupleGuardDispatch

  @before """
  defmodule Bad do
    def run(e1, e2) do
      case {e1, e2} do
        {e1, e2} when e1 < e2 -> :left
        {e1, e2} when e1 > e2 -> :right
        _ -> :equal
      end
    end
  end
  """

  test "case on a {a, b} tuple with guards → guarded heads preserves dispatch" do
    assert_equivalent_module(@before,
      rule: NoCaseTupleGuardDispatch,
      call: {:run, 2},
      inputs: [{1, 2}, {2, 1}, {1, 1}, {1, 1.0}, {:a, :b}]
    )
  end
end
