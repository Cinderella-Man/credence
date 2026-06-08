defmodule Credence.Pattern.NoStringLengthForCharCheckEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), Unicode dimension — always safe.

  `String.length(s) == 1` → `match?([_], String.graphemes(s))`. Both count by
  grapheme, so the boolean agrees on every string — empty, single, multi-char,
  and multi-codepoint graphemes (decomposed accents, flags) which are one
  grapheme. No assumption needed.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoStringLengthForCharCheck

  test "String.length(s) == 1 → match?([_], graphemes) preserves the boolean over Unicode" do
    assert_equivalent(
      """
      String.length(s) == 1
      """,
      rule: NoStringLengthForCharCheck,
      vars: [:s],
      inputs: B.unicode_strings()
    )
  end
end
