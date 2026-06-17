defmodule Credence.Pattern.NoRedundantUnderscoreBindEquivalenceTest do
  @moduledoc """
  The `_ = var` pattern in a function head is purely syntactic sugar —
  it matches anything and binds to `var`, identical to just `var`.
  No runtime behaviour changes, so this is a cosmetic rewrite.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  test "fix preserves behaviour" do
    mark_equivalence_cosmetic(
      "_ = var is syntactic sugar for var in pattern position; no runtime change"
    )
  end
end
