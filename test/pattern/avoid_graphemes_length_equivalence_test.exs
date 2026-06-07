defmodule Credence.Pattern.AvoidGraphemesLengthEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), Unicode. `length(String.graphemes(string))` →
  `String.length(string)`. Both count graphemes; agree on all Unicode.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.AvoidGraphemesLength

  test "length(String.graphemes(string)) → String.length preserves the count over Unicode" do
    assert_equivalent(
      """
      length(String.graphemes(string))
      """,
      rule: AvoidGraphemesLength,
      vars: [:string],
      inputs: B.unicode_strings()
    )
  end
end
