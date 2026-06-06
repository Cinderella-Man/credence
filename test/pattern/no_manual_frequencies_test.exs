defmodule Credence.Pattern.NoManualFrequenciesTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoManualFrequencies

  defp check(code), do: NoManualFrequencies.check(Sourceror.parse_string!(code), [])
  defp fix(code), do: Credence.RuleHelpers.apply_rule_fix(NoManualFrequencies, code, [])

  # Build `fn list -> <expr> end` and evaluate it to a real function.
  defp eval1(expr) do
    {f, _} = Code.eval_string("fn list -> #{expr} end")
    f
  end

  # The core guarantee: the rewrite must be behaviour-preserving. Fix the reduce,
  # confirm the rule actually fired (no Enum.reduce left), then run BOTH the
  # original and the fixed code over every input and assert the resulting maps are
  # element-for-element identical. This is what proves safety across edge cases —
  # not the textual shape of the output.
  defp assert_preserves(reduce_expr, inputs) do
    fixed = fix(reduce_expr)

    refute fixed =~ "Enum.reduce",
           "expected the rule to rewrite the reduce, but it was left unchanged:\n#{fixed}"

    orig = eval1(reduce_expr)
    new = eval1(fixed)

    for input <- inputs do
      assert orig.(input) == new.(input),
             """
             behaviour changed on input #{inspect(input)}
               original => #{inspect(orig.(input))}
               fixed    => #{inspect(new.(input))}
               fixed code: #{String.trim(fixed)}
             """
    end
  end

  defp identity_reduce,
    do: "Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, x, 1, &(&1 + 1)) end)"

  defp derived_reduce(key_expr),
    do: "Enum.reduce(list, %{}, fn w, acc -> Map.update(acc, #{key_expr}, 1, &(&1 + 1)) end)"

  # ── input batteries ───────────────────────────────────────────────
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
    ["Café", "Café", "café", "CAFÉ"],
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

  describe "behaviour preservation (original vs fixed produce identical maps)" do
    test "identity key → Enum.frequencies/1, across all term kinds" do
      assert_preserves(identity_reduce(), @term_lists)
    end

    test "derived key String.downcase/1 → frequencies_by, weird + common strings" do
      assert_preserves(derived_reduce("String.downcase(w)"), @string_lists)
    end

    test "derived key String.length/1 → frequencies_by (grapheme counts)" do
      assert_preserves(derived_reduce("String.length(w)"), @string_lists)
    end

    test "derived key String.first/1 → frequencies_by (nil on empty string)" do
      assert_preserves(derived_reduce("String.first(w)"), @string_lists)
    end

    test "derived key rem(x, 3) → frequencies_by, incl. negatives and zero" do
      reduce = "Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, rem(x, 3), 1, &(&1 + 1)) end)"

      assert_preserves(reduce, [
        [],
        [1, 2, 3, 4, 5, 6],
        [-1, -2, -3, -4, -5],
        [0, 0, 3, 6, 9],
        Enum.to_list(-50..50)
      ])
    end

    test "derived key with an arithmetic expression → frequencies_by" do
      reduce = "Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, x * x, 1, &(&1 + 1)) end)"
      assert_preserves(reduce, [[], [-2, 2, -3, 3], [0, 1, 2, 2, 2], Enum.to_list(1..100)])
    end
  end

  describe "check — fires on the safe frequency-counting shapes" do
    test "identity key, piped" do
      code = """
      defmodule Bad do
        def char_freq(string) do
          string
          |> String.graphemes()
          |> Enum.reduce(%{}, fn char, counts ->
            Map.update(counts, char, 1, &(&1 + 1))
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert %Issue{rule: :no_manual_frequencies} = hd(issues)
      assert hd(issues).meta.line != nil
    end

    test "identity key, direct (non-piped)" do
      code = """
      Enum.reduce(words, %{}, fn word, acc ->
        Map.update(acc, word, 1, &(&1 + 1))
      end)
      """

      assert length(check(code)) == 1
    end

    test "derived key (String.downcase)" do
      code = """
      Enum.reduce(words, %{}, fn word, acc ->
        Map.update(acc, String.downcase(word), 1, &(&1 + 1))
      end)
      """

      assert length(check(code)) == 1
    end

    test "fn-form increment (fn n -> n + 1 end)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update(acc, item, 1, fn n -> n + 1 end)
      end)
      """

      assert length(check(code)) == 1
    end
  end

  describe "check — does NOT fire (no safe same-answer rewrite)" do
    test "already uses Enum.frequencies/1" do
      code = """
      string |> String.graphemes() |> Enum.frequencies()
      """

      assert check(code) == []
    end

    test "non-empty initial accumulator" do
      code = """
      Enum.reduce(list, initial, fn item, acc ->
        Map.update(acc, item, 1, &(&1 + 1))
      end)
      """

      assert check(code) == []
    end

    test "no Map.update (Map.put)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.put(acc, item, true)
      end)
      """

      assert check(code) == []
    end

    test "group-by pattern (list default, not a count)" do
      code = """
      Enum.reduce(words, %{}, fn word, acc ->
        Map.update(acc, String.first(word), [word], fn existing -> [word | existing] end)
      end)
      """

      assert check(code) == []
    end

    test "non-1 default" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update(acc, item, 0, &(&1 + 1))
      end)
      """

      assert check(code) == []
    end

    test "weighted increment (+2 is not a plain count)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update(acc, item, 1, &(&1 + 2))
      end)
      """

      assert check(code) == []
    end

    test "Map.update! variant (raises on the first, missing key)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update!(acc, item, &(&1 + 1))
      end)
      """

      assert check(code) == []
    end

    test "key references the accumulator (can't extract to a key function)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update(acc, map_size(acc), 1, &(&1 + 1))
      end)
      """

      assert check(code) == []
    end
  end

  describe "fix — emits the right call" do
    test "identity key → Enum.frequencies/1 (piped and direct)" do
      direct =
        fix(
          "Enum.reduce(list, %{}, fn item, counts -> Map.update(counts, item, 1, &(&1 + 1)) end)"
        )

      assert direct =~ "Enum.frequencies(list)"
      refute direct =~ "Enum.reduce"

      piped =
        fix(
          "list |> Enum.reduce(%{}, fn item, counts -> Map.update(counts, item, 1, &(&1 + 1)) end)"
        )

      assert piped =~ "Enum.frequencies(list)"
      refute piped =~ "Enum.reduce"
    end

    test "derived key → Enum.frequencies_by/2" do
      result =
        fix(
          "Enum.reduce(words, %{}, fn word, acc -> Map.update(acc, String.downcase(word), 1, &(&1 + 1)) end)"
        )

      assert result =~ "Enum.frequencies_by(words, fn word -> String.downcase(word) end)"
      refute result =~ "Enum.reduce"
    end

    test "leaves a non-frequency reduction alone" do
      result = fix("Enum.reduce(list, %{}, fn item, acc -> Map.put(acc, item, true) end)")
      assert result =~ "Enum.reduce"
      refute result =~ "Enum.frequencies"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def count(list) do
          total = length(list)

          freqs =
            Enum.reduce(list, %{}, fn item, acc ->
              Map.update(acc, item, 1, &(&1 + 1))
            end)

          {total, freqs}
        end
      end
      """

      result = fix(code)
      assert result =~ "length(list)"
      assert result =~ "Enum.frequencies(list)"
      assert result =~ "{total, freqs}"
    end

    test "round-trip: fixed code produces no further issues" do
      for code <- [
            "Enum.reduce(list, %{}, fn item, counts -> Map.update(counts, item, 1, &(&1 + 1)) end)",
            "Enum.reduce(words, %{}, fn word, acc -> Map.update(acc, String.downcase(word), 1, &(&1 + 1)) end)"
          ] do
        fixed = fix(code)
        assert check(fixed) == []
      end
    end
  end
end
