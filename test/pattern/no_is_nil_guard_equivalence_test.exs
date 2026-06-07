defmodule Credence.Pattern.NoIsNilGuardEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `def foo(x) when is_nil(x)` → `def foo(nil)`. `is_nil(x)` is
  true exactly for `nil`, so the pattern clause matches the same inputs — `false`
  and other falsy-but-not-nil values still fall through to the next clause.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoIsNilGuard

  @before """
  defmodule Bad do
    def foo(x) when is_nil(x), do: :bar
    def foo(_x), do: :baz
  end
  """

  test "is_nil guard → nil pattern preserves dispatch incl. false" do
    assert_equivalent_module(@before,
      rule: NoIsNilGuard,
      call: {:foo, 1},
      inputs: [nil, false, 1, :x, "s", 0]
    )
  end
end
