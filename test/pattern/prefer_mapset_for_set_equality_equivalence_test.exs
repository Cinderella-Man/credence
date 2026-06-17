defmodule Credence.Pattern.PreferMapsetForSetEqualityEquivalenceTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapsetForSetEquality

  test "fix preserves behaviour" do
    assert_equivalent(
      """
      first_set = String.codepoints(first) |> Enum.uniq() |> Enum.sort()
      second_set = String.codepoints(second) |> Enum.uniq() |> Enum.sort()
      first_set == second_set
      """,
      rule: PreferMapsetForSetEquality,
      vars: [:first, :second],
      inputs: [
        {"", ""},
        {"abc", "abc"},
        {"abc", "cba"},
        {"aab", "ba"},
        {"hello", "world"},
        {"café", "éfac"},
        {"👨‍👩‍👧", "👨‍👩‍👧"}
      ]
    )
  end
end
