defmodule Credence.Pattern.NoNegativeStepInStringSliceEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), bounds dimension.
  `String.slice(str, n..-1)` → `String.slice(str, n..-1//1)`. In Elixir 1.19.5,
  `String.slice` handles the deprecated `n..-1` range (step -1) gracefully and
  returns the same result as `n..-1//1`, so the fix is behaviour-preserving.
  The input set covers short/empty strings, out-of-bounds indices, negative
  indices, and Unicode.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoNegativeStepInStringSlice

  test "String.slice(str, n..-1) → String.slice(str, n..-1//1) preserves behaviour" do
    assert_equivalent(
      "String.slice(str, n..-1)",
      rule: NoNegativeStepInStringSlice,
      vars: [:str, :n],
      inputs: [
        {"hello", 0},
        {"hello", 1},
        {"hello", 2},
        {"hello", 3},
        {"hello", 10},
        {"", 0},
        {"", 1},
        {"abc", -1},
        {"abc", -2},
        {"abc", -10},
        {"café", 1},
        {"👨‍👩‍👧", 0},
        {"🇵🇱", 0}
      ]
    )
  end
end
