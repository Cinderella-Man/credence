defmodule Credence.Pattern.NoGraphemePalindromeEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), Unicode dimension — always safe.

  `graphemes = String.graphemes(s); graphemes == Enum.reverse(graphemes)` →
  `s == String.reverse(s)`. Both sides compare by grapheme, so they agree on
  every string, including decomposed accents and flags. No assumption needed.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoGraphemePalindrome

  @expr """
  graphemes = String.graphemes(s)
  graphemes == Enum.reverse(graphemes)
  """

  test "grapheme palindrome check → String.reverse comparison preserves behaviour over Unicode" do
    assert_equivalent(@expr,
      rule: NoGraphemePalindrome,
      vars: [:s],
      inputs: B.unicode_strings()
    )
  end
end
