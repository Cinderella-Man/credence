defmodule Credence.Pattern.NonGroupedClausesEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Moves a function's scattered clauses to be adjacent. The
  *relative* order of each function's own clauses is preserved (only unrelated defs
  in between move), so dispatch for every function is unchanged. Input set exercises
  both the regrouped function and the one that was moved.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NonGroupedClauses

  @before """
  defmodule Bad do
    def foo(1), do: 1
    def bar(x), do: x
    def foo(x), do: x + 1
  end
  """

  test "regrouping clauses preserves foo/1 dispatch (relative order intact)" do
    assert_equivalent_module(@before,
      rule: NonGroupedClauses,
      call: {:foo, 1},
      inputs: [1, 2, 5, 0, -3]
    )
  end

  test "regrouping clauses leaves the moved bar/1 unchanged" do
    assert_equivalent_module(@before,
      rule: NonGroupedClauses,
      call: {:bar, 1},
      inputs: [1, :x, "s", 42]
    )
  end
end
