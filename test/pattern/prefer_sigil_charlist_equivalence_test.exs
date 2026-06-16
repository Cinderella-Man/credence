defmodule Credence.Pattern.PreferSigilCharlistEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `'abc'` and `~c"abc"` are the SAME value (`[97, 98, 99]`)
  — the rewrite only changes the source representation, so it is behaviour-
  identical by construction. Membership over a varying codepoint discriminates
  while exercising the rewritten literal.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferSigilCharlist

  test "'abc' → ~c\"abc\" is value-identical" do
    assert_equivalent(
      "c in 'abc'",
      rule: PreferSigilCharlist,
      vars: [:c],
      inputs: [?a, ?z, ?1, 97, 0, -1]
    )
  end
end
