defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicateEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), Unicode. `String.graphemes(str) |> Enum.count(&(&1 == "a"))`
  → `String.count(str, "a")`. Both count occurrences of the single grapheme "a".
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.AvoidGraphemesEnumCountWithPredicate

  test "graphemes |> count(== \"a\") → String.count(str, \"a\") preserves the count" do
    assert_equivalent(~s[String.graphemes(str) |> Enum.count(&(&1 == "a"))],
      rule: AvoidGraphemesEnumCountWithPredicate,
      vars: [:str],
      inputs: ["", "a", "aXaXa", "banana", :unicode.characters_to_nfd_binary("café")]
    )
  end
end
