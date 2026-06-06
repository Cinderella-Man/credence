defmodule Credence.EquivalenceBatteries do
  @moduledoc """
  Curated, deterministic adversarial input batteries for behaviour-equivalence
  tests, grouped by data shape. Each function returns a list of inputs an
  author picks by recognizing their rule's risk dimension.

  Curated-only feeds the assertions (no random seed flakes). A StreamData layer,
  if added later, stays additive and non-gating.

  Annotated with the taxonomy class each dimension witnesses, so picking a
  battery is "which way could *this* fix break?", not guesswork.
  """

  @doc """
  Any-term lists. Witnesses: value-kind traps (`1` vs `1.0` are distinct map
  keys / compare equal-not-identical), nil/false elements, empty/single, large.
  """
  def term_lists do
    [
      [],
      [1],
      [1, 2, 3, 4, 5],
      [3, 1, 2, 1, 3, 2],
      [:a, :b, :a, :c],
      ["x", "x", "y"],
      # value-kind trap: 1 and 1.0 are distinct as keys, equal-not-identical in <
      [1, 1.0, 1, 1.0, 2],
      # nil / false / true as elements
      [nil, false, nil, true, false],
      Enum.map(1..200, fn i -> rem(i, 7) end)
    ]
  end

  @doc """
  Signed integers incl. negatives and zero. Witnesses: negative-index/count,
  sign-dependent arithmetic (`rem`, `div`).
  """
  def signed_integers do
    [[], [0], [1, 2, 3], [-1, -2, -3], [0, 0, 0], [-5, 0, 5, 10, -10], Enum.to_list(-20..20)]
  end

  @doc """
  Strings exercising the nasty Unicode cases: precomposed-vs-combining accents,
  ZWJ-family emoji, regional-indicator flags, eszett, fullwidth, CJK. Witnesses:
  codepoint-vs-grapheme divergence, multi-codepoint graphemes.
  """
  def unicode_strings do
    [
      "",
      "abc",
      # precomposed é (U+00E9) vs decomposed e + combining acute (U+0301)
      "café",
      "café",
      # ZWJ family emoji: 1 grapheme, multiple codepoints
      "👨‍👩‍👧",
      # regional-indicator flag: 1 grapheme, 2 codepoints
      "🇵🇱",
      # eszett: downcase("STRASSE") != "straße"
      "straße",
      # CJK + fullwidth
      "日本語ＡＢＣ"
    ]
  end

  @doc """
  Strings whose every grapheme is a **single codepoint** — the domain in which
  codepoint-level and grapheme-level string ops agree. Use for rules safe only
  under the `single_codepoint_graphemes` assumption.
  """
  def single_codepoint_strings do
    [
      "",
      "abc",
      "hello world",
      # precomposed accent (NFC): é is U+00E9, one codepoint
      :unicode.characters_to_nfc_binary("café"),
      # Greek with precomposed accent
      "Ωμέγα",
      # CJK + fullwidth: each one codepoint
      "日本語ＡＢＣ"
    ]
  end

  @doc """
  Strings with **multi-codepoint graphemes** (decomposed accents, ZWJ emoji,
  regional-indicator flags) — outside `single_codepoint_graphemes`, where
  codepoint-level reversal diverges from grapheme-level.
  """
  def multi_codepoint_strings do
    [
      # decomposed é (NFD): "e" + combining acute U+0301
      :unicode.characters_to_nfd_binary("café"),
      # regional-indicator flag: 1 grapheme, 2 codepoints
      "🇵🇱",
      # ZWJ family emoji: 1 grapheme, many codepoints
      "👨‍👩‍👧"
    ]
  end

  @doc """
  Lists with duplicate / equal-key elements to witness **sort stability**:
  a stable sort keeps equal elements in input order; a naive sort-then-reverse
  or strict-`<`/`>` comparator does not.
  """
  def stability_lists do
    [
      [],
      [1, 1, 1],
      [3, 1, 2, 1, 3, 2],
      [2, 2, 1, 1, 3, 3],
      [5, 4, 3, 2, 1],
      [1, 2, 3, 4, 5],
      Enum.map(1..50, fn i -> rem(i, 3) end)
    ]
  end
end
