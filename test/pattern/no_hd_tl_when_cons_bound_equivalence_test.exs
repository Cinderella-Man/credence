defmodule Credence.Pattern.NoHdTlWhenConsBoundEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). When the head pattern already binds a cons
  (`def first(list = [_ | _])`), calling `hd(list)`/`tl(list)` is redundant — use
  the bound head/tail. The cons pattern guarantees a non-empty list, so the bound
  element equals `hd`/`tl` exactly.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoHdTlWhenConsBound

  @before """
  defmodule Bad do
    def first(list = [_ | _]), do: hd(list)
  end
  """

  test "hd(list) under a bound cons head → the bound head preserves the value" do
    assert_equivalent_module(@before,
      rule: NoHdTlWhenConsBound,
      call: {:first, 1},
      inputs: [[1, 2], [5], [:a, :b, :c], [nil, 1]]
    )
  end
end
