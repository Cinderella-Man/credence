defmodule Credence.Pattern.PreferGraphemesForCharacterUniquenessEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). Under the `single_codepoint_graphemes` assumption,
  `String.to_charlist(s) |> Enum.uniq() |> Enum.count() |> (&(&1 == String.length(s))).()`
  and the rewrite
  `String.graphemes(s) |> Enum.uniq() |> Enum.count() |> then(&(&1 == String.length(s)))`
  agree because every grapheme is exactly one codepoint, so the two
  decompositions produce the same count.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferGraphemesForCharacterUniqueness
  alias Credence.EquivalenceInputs, as: B

  test "fix preserves behaviour for single-codepoint strings" do
    assert_equivalent(
      """
      (String.to_charlist(string)
       |> Enum.uniq()
       |> Enum.count()
       |> (&(&1 == String.length(string))).())
      """,
      rule: PreferGraphemesForCharacterUniqueness,
      vars: [:string],
      inputs: B.single_codepoint_strings()
    )
  end
end
