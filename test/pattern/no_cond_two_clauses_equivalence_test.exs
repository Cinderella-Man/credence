defmodule Credence.Pattern.NoCondTwoClausesEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). A two-clause `cond` whose second clause is `true ->` is an
  `if/else`. `cond do c -> a; true -> b end` → `if c, do: a, else: b`. Input set
  drives the condition both ways and over edge values.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoCondTwoClauses

  @expr """
  cond do
    x > 0 -> :pos
    true -> :nonpos
  end
  """

  test "two-clause cond (true fallback) → if/else preserves the branch taken" do
    assert_equivalent(@expr,
      rule: NoCondTwoClauses,
      vars: [:x],
      inputs: [1, -1, 0, 100, -100]
    )
  end
end
