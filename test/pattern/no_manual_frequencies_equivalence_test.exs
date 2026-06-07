defmodule Credence.Pattern.NoManualFrequenciesEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). Manual `Enum.reduce(list, %{}, fn ... Map.update ...)` →
  `Enum.frequencies/1` (identity key) or `Enum.frequencies_by/2` (derived key).
  Both count occurrences with strict-`===` keys, so the `1` vs `1.0` value-kind
  case stays distinct — over every term kind and the nasty Unicode string cases.

  This is the behaviour-preservation suite the `BehaviourEquivalence` harness was
  generalized from (it formerly lived in the fix test as `eval1`/`assert_preserves`;
  `assert_equivalent` runs the same original-vs-fixed comparison).
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualFrequencies

  defp identity_reduce,
    do: "Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, x, 1, &(&1 + 1)) end)"

  defp derived_reduce(key_expr),
    do: "Enum.reduce(list, %{}, fn w, acc -> Map.update(acc, #{key_expr}, 1, &(&1 + 1)) end)"

  # Any-term lists (for the identity-key fix → Enum.frequencies/1).
  @term_lists [
    # empty / single
    [],
    [1],
    # common: ints, atoms, strings, tuples, lists, mixed
    [1, 1, 2, 3, 3, 3],
    [:a, :b, :a, :c, :a, :b],
    ["x", "x", "y", "x"],
    [{1, 2}, {1, 2}, {3, 4}],
    [[1], [1], [2], []],
    [1, :a, "1", {1}, 1, "1"],
    # value-kind trap: 1 and 1.0 are distinct map keys, must stay distinct
    [1, 1.0, 1, 1.0, 2],
    # nil / false as keys
    [nil, nil, false, false, nil, true],
    # large
    Enum.map(1..500, fn i -> rem(i, 13) end)
  ]

  # String lists exercising the nasty Unicode cases for derived string keys.
  @string_lists [
    # empty / single
    [],
    ["a"],
    # common ASCII, with case variation (so downcase actually does work)
    ["a", "a", "b", "a", "c", "b"],
    ["A", "a", "B", "b", "A", "a"],
    # precomposed é (U+00E9) vs decomposed e + combining acute (U+0301) vs cases —
    # downcase does NOT unify these, but neither form should either
    ["Café", "Café", "café", "CAFÉ"],
    # ZWJ family emoji (1 grapheme / 5 codepoints) + regional-indicator flags
    ["👨‍👩‍👧", "👨‍👩‍👧", "🇵🇱", "🇵🇱", "🇩🇪"],
    # eszett: String.downcase("STRASSE") != "straße"
    ["straße", "STRASSE", "Straße", "strasse"],
    # empty strings, whitespace
    ["", "", " ", "\t", "a", "A"],
    # non-Latin scripts + fullwidth
    ["Ωμέγα", "ωμέγα", "日本語", "日本語", "ＡＢＣ", "abc"],
    # large
    Enum.map(1..300, fn i -> "Word#{rem(i, 7)}" end)
  ]

  test "identity key → Enum.frequencies/1, across all term kinds" do
    assert_equivalent(identity_reduce(),
      rule: NoManualFrequencies,
      vars: [:list],
      inputs: @term_lists
    )
  end

  test "derived key String.downcase/1 → frequencies_by, weird + common strings" do
    assert_equivalent(derived_reduce("String.downcase(w)"),
      rule: NoManualFrequencies,
      vars: [:list],
      inputs: @string_lists
    )
  end

  test "derived key String.length/1 → frequencies_by (grapheme counts)" do
    assert_equivalent(derived_reduce("String.length(w)"),
      rule: NoManualFrequencies,
      vars: [:list],
      inputs: @string_lists
    )
  end

  test "derived key String.first/1 → frequencies_by (nil on empty string)" do
    assert_equivalent(derived_reduce("String.first(w)"),
      rule: NoManualFrequencies,
      vars: [:list],
      inputs: @string_lists
    )
  end

  test "derived key rem(x, 3) → frequencies_by, incl. negatives and zero" do
    assert_equivalent(
      """
      Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, rem(x, 3), 1, &(&1 + 1)) end)
      """,
      rule: NoManualFrequencies,
      vars: [:list],
      inputs: [
        [],
        [1, 2, 3, 4, 5, 6],
        [-1, -2, -3, -4, -5],
        [0, 0, 3, 6, 9],
        Enum.to_list(-50..50)
      ]
    )
  end

  test "derived key with an arithmetic expression → frequencies_by" do
    assert_equivalent(
      """
      Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, x * x, 1, &(&1 + 1)) end)
      """,
      rule: NoManualFrequencies,
      vars: [:list],
      inputs: [[], [-2, 2, -3, 3], [0, 1, 2, 2, 2], Enum.to_list(1..100)]
    )
  end
end
