defmodule Credence.Pattern.NoDuplicateFunctionClausesEquivalenceTest do
  @moduledoc """
  Tier 2 (module-level) — the fix removes an unreachable duplicate clause.

  The duplicate clause has identical argument patterns, so it never matches at
  runtime. Removing it changes no emitted behaviour. We compile before/after
  modules and invoke `bar/2` over discriminating inputs to prove equivalence.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  alias Credence.Pattern.NoDuplicateFunctionClauses

  test "fix preserves behaviour for duplicate function clauses" do
    assert_equivalent_module(
      """
      defmodule DuplicateExample do
        def bar(x, y), do: {x, y}
        def bar(x, y), do: {x, y}
      end
      """,
      rule: NoDuplicateFunctionClauses,
      call: {:bar, 2},
      inputs: [
        {1, 2},
        {:a, :b},
        {[], [1, 2, 3]},
        {"hello", :world},
        {true, false}
      ]
    )
  end
end
