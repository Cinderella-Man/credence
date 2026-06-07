defmodule Credence.Pattern.NoGuardEqualityForPatternMatchEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `def f(x) when x == :literal` → `def f(:literal)`.

  Only ATOM and STRING literals are rewritten. For those, value equality (`==`)
  and pattern matching (`===`) agree — there is no cross-type value-equal partner
  — so the pattern head selects exactly the same inputs as the guard.

  Number literals are deliberately NOT fixed: `when n == 0` matches `0.0` but the
  head `f(0)` does not, which would change dispatch. (That narrowing is pinned by
  the check/fix tests' negative cases.)
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoGuardEqualityForPatternMatch

  @before """
  defmodule Bad do
    def process(action) when action == :stop, do: :halted
    def process(_action), do: :running
  end
  """

  test "atom-equality guard → pattern head preserves dispatch" do
    assert_equivalent_module(@before,
      rule: NoGuardEqualityForPatternMatch,
      call: {:process, 1},
      inputs: [:stop, :go, :run, nil, 1, "stop"]
    )
  end
end
