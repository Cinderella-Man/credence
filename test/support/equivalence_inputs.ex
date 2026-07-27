defmodule Credence.EquivalenceInputs do
  @moduledoc """
  Curated, deterministic adversarial input sets for behaviour-equivalence
  tests, grouped by data shape. Each function returns a list of inputs an
  author picks by recognizing their rule's risk dimension.

  Curated-only feeds the assertions (no random seed flakes). A StreamData layer,
  if added later, stays additive and non-gating.

  Annotated with the taxonomy class each dimension witnesses, so picking an
  input set is "which way could *this* fix break?", not guesswork.
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
      # value-kind trap at the MAX: the entry above ties only at the minimum,
      # which hides first-vs-last-maximal divergences (sort|>at(-1) vs Enum.max
      # — the docs/14 E1 hole that shipped two live bugs). Keep both shapes.
      [1.0, 1],
      [1, 2, 2.0],
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
      # ==-equal but ===-distinct ties (int vs float): a rewrite that reorders
      # a tie group is invisible to all-integer lists
      [1, 1.0, 1],
      [2.0, 2],
      Enum.map(1..50, fn i -> rem(i, 3) end)
    ]
  end

  @doc """
  Maps. Witnesses: **key identity** — `1` and `1.0` are DISTINCT map keys even
  though `1 == 1.0`, so a rewrite that routes a lookup through a different
  equality (`Enum.find` on `==`, say) diverges only on a map that holds both.
  Also: empty/single, atom-vs-string keys, a nested value, and a map large
  enough to leave the small-map representation (>32 keys), where iteration
  order stops matching term order.
  """
  def maps do
    [
      %{},
      %{a: 1},
      %{a: 1, b: 2, c: 3},
      # key-identity trap: two keys that are `==` but not `===`
      %{1 => :int, 1.0 => :float},
      # mixed key types — anything that assumes atom keys breaks here
      %{:a => 1, "a" => 2, 1 => 3},
      # nested value: a fix that rebuilds the map must not flatten it
      %{outer: %{inner: [1, 2, 3]}},
      %{a: nil, b: false},
      # >32 keys: leaves the flatmap representation, iteration order changes
      Map.new(1..40, fn i -> {i, rem(i, 5)} end)
    ]
  end

  @doc """
  Keyword lists. Witnesses: **duplicate keys**, which a keyword list keeps and a
  map silently collapses — the classic divergence when a fix rewrites
  `Keyword.get/2` as `Map.get/2` or pipes a keyword list through `Map.new/1`.
  `Keyword.get` returns the FIRST duplicate; `Map.new` keeps the LAST. Also:
  order significance, empty/single, and a value that is itself a keyword list.
  """
  def keyword_lists do
    [
      [],
      [a: 1],
      [a: 1, b: 2],
      [a: 1, b: 2, c: 3],
      # duplicate keys: Keyword.get -> 1, Map.new |> Map.get -> 3
      [a: 1, b: 2, a: 3],
      [a: 1, a: 2, a: 3],
      # order significance: same pairs, different order
      [b: 2, a: 1],
      [a: nil, b: false],
      [opts: [nested: true], timeout: 5000]
    ]
  end

  @doc """
  Tuples. Witnesses: **arity dependence** — `elem/2` and pattern matches are
  arity-exact, so a fix that reshapes a tuple breaks on every other arity. Also:
  the empty tuple, the 1-tuple (easy to confuse with a bare value), the
  `{:ok, _}` / `{:error, _}` result idiom, and nesting.
  """
  def tuples do
    [
      {},
      {1},
      {1, 2},
      {1, 2, 3},
      {:ok, :value},
      {:error, :reason},
      # nested: a rewrite that flattens changes the shape a caller matches on
      {:ok, {1, [2, 3]}},
      {nil, false},
      List.to_tuple(Enum.to_list(1..20))
    ]
  end

  @doc """
  Mixed integers and floats. Witnesses: the int/float divergences that survive
  `==` — `div/2` truncates toward zero while `Float.floor/1` does not, `rem/2`
  takes the sign of the DIVIDEND (unlike Python's `%`, the transplant several
  rules exist to repair), `0.0` and `-0.0` are `==` but not `===`, and integers
  are arbitrary-precision while floats are not, so a large integer survives a
  round trip that a float does not.
  """
  def mixed_numeric do
    [
      0,
      1,
      -1,
      # == but not ===; also 1/1 is 1.0, not 1
      1.0,
      -1.0,
      # -0.0 == 0.0 is true, -0.0 === 0.0 is false
      0.0,
      -0.0,
      7,
      -7,
      2.5,
      -2.5,
      # rem/div sign behaviour: rem(-7, 3) is -1 in Elixir, 2 in Python
      -7.5,
      # beyond float precision: an integer that cannot round-trip through float
      9_007_199_254_740_993,
      1.0e308,
      1.0e-308
    ]
  end
end
