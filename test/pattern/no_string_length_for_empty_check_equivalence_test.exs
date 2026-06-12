defmodule Credence.Pattern.NoStringLengthForEmptyCheckEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `String.length(String.trim(s)) == 0` → `String.trim(s) ==
  ""`. For every string `s` the two agree (length 0 ⇔ the trimmed string is "").
  The argument `String.trim(s)` is evaluated first on BOTH sides, so a non-string
  `s` raises identically (ArgumentError) before either comparison runs — no
  divergence. Inputs cover empty/non-empty strings and non-strings.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoStringLengthForEmptyCheck

  test "String.length(String.trim(s)) == 0 → String.trim(s) == \"\"" do
    assert_equivalent(
      """
      String.length(String.trim(s)) == 0
      """,
      rule: NoStringLengthForEmptyCheck,
      vars: [:s],
      inputs: B.unicode_strings() ++ ["   ", "  x  ", 123, :atom, nil]
    )
  end
end
