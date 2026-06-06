defmodule Credence.Pattern.NoGraphemePalindromeCheckEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoGraphemePalindromeCheck

  # Firing snippets lifted from no_grapheme_palindrome_check_check_test.exs:
  #   (none auto-extracted — see the check test)

  test "no_grapheme_palindrome_check: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoGraphemePalindromeCheck,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
