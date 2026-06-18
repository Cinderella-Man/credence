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

  # The regression case: `x == nil` → `f(nil)`. Critically, `nil` and `false`
  # are distinct — `x == nil` is FALSE for `false` — so `false` must still route
  # to the catch-all, not the nil clause. Inputs exercise nil, false, and others.
  @nil_before """
  defmodule Bad do
    def classify(x) when x == nil, do: :nothing
    def classify(_x), do: :something
  end
  """

  test "nil-equality guard → nil pattern head preserves dispatch (nil != false)" do
    assert_equivalent_module(@nil_before,
      rule: NoGuardEqualityForPatternMatch,
      call: {:classify, 1},
      inputs: [nil, false, true, :nothing, 0, "", [], "nil"]
    )
  end

  # Multi-clause shadowing shape (mirrors tds): the nil clause is NOT last, so a
  # broken fix (guard dropped, nil not substituted) would shadow the later
  # clauses. Inputs prove every non-nil value still routes correctly.
  @multi_before """
  defmodule Bad do
    def size(n) when n == nil, do: 0
    def size(n) when is_integer(n), do: n
    def size(_), do: -1
  end
  """

  test "nil clause before other clauses preserves dispatch for all inputs" do
    assert_equivalent_module(@multi_before,
      rule: NoGuardEqualityForPatternMatch,
      call: {:size, 1},
      inputs: [nil, 0, 7, -3, :atom, "str", false]
    )
  end
end
