defmodule Credence.Pattern.NoGraphemePalindromeCheckEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), Unicode dimension — always safe.

  `graphemes = String.graphemes(s); graphemes == Enum.reverse(graphemes)` →
  `s == String.reverse(s)`. Both sides compare by grapheme, so they agree on
  every string, including decomposed accents and flags. No assumption needed.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoGraphemePalindromeCheck

  @expr """
  graphemes = String.graphemes(s)
  graphemes == Enum.reverse(graphemes)
  """

  test "grapheme palindrome check → String.reverse comparison preserves behaviour over Unicode" do
    assert_equivalent(@expr,
      rule: NoGraphemePalindromeCheck,
      vars: [:s],
      inputs: B.unicode_strings()
    )
  end
end
