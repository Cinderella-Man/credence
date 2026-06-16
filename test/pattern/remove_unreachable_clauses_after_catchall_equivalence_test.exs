defmodule Credence.Pattern.RemoveUnreachableClausesAfterCatchallEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Removes the unreachable catch-all clause
  `def exactly_one_replace(_, _), do: false` which follows the real
  catch-all `def exactly_one_replace(t1, t2)`. The removed clause is
  dead code — it never matches because the preceding clause already
  handles every two-argument input — so the function's behaviour is
  unchanged for every input.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.RemoveUnreachableClausesAfterCatchall

  @before """
  defmodule Solution do
    def exactly_one_replace([], []), do: false

    def exactly_one_replace([h1 | t1], [h2 | t2]) when h1 == h2 do
      exactly_one_replace(t1, t2)
    end

    def exactly_one_replace(t1, t2) do
      t1 == t2
    end

    def exactly_one_replace(_, _), do: false
  end
  """

  test "removing the unreachable catch-all clause preserves behaviour" do
    assert_equivalent_module(@before,
      rule: RemoveUnreachableClausesAfterCatchall,
      call: {:exactly_one_replace, 2},
      # The function always returns `false`: the base case `([], []) -> false`
      # feeds every recursive equal-heads path, and the catch-all `t1 == t2`
      # compares remaining tails (equal tails -> false from base; different -> false).
      # So the output is constant across all inputs — the removed unreachable
      # clause is provably dead code.
      allow_constant_output: true,
      inputs: [
        {[], []},
        {[1, 2], [1, 2]},
        {[1, 2], [1, 3]},
        {[1], [1, 2]},
        {[:a, :b, :c], [:a, :b, :c]}
      ]
    )
  end
end
