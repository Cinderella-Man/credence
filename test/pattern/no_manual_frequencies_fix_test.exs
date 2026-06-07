defmodule Credence.Pattern.NoManualFrequenciesFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualFrequencies

  defp check(code), do: NoManualFrequencies.check(Sourceror.parse_string!(code), [])
  defp fix(code), do: Credence.RuleHelpers.apply_rule_fix(NoManualFrequencies, code, [])

  describe "fix output (whole-string compare)" do
    test "identity key collapses to Enum.frequencies/1, surrounding code preserved" do
      code = """
      defmodule Bad do
        def count(list) do
          total = length(list)

          freqs = Enum.reduce(list, %{}, fn item, acc -> Map.update(acc, item, 1, &(&1 + 1)) end)

          {total, freqs}
        end
      end
      """

      expected = """
      defmodule Bad do
        def count(list) do
          total = length(list)

          freqs = Enum.frequencies(list)

          {total, freqs}
        end
      end
      """

      assert fix(code) == expected
    end

    test "piped identity key collapses to Enum.frequencies/1" do
      code = """
      defmodule Bad do
        def count(list) do
          list |> Enum.reduce(%{}, fn item, acc -> Map.update(acc, item, 1, &(&1 + 1)) end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def count(list) do
          Enum.frequencies(list)
        end
      end
      """

      assert fix(code) == expected
    end

    test "derived key becomes Enum.frequencies_by/2 (key carried over verbatim)" do
      code = """
      defmodule Bad do
        def count(words) do
          Enum.reduce(words, %{}, fn word, acc -> Map.update(acc, String.downcase(word), 1, &(&1 + 1)) end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def count(words) do
          Enum.frequencies_by(words, fn word -> String.downcase(word) end)
        end
      end
      """

      assert fix(code) == expected
    end

    test "non-frequency reduce is left unchanged" do
      code = """
      defmodule Safe do
        def group(list) do
          Enum.reduce(list, %{}, fn item, acc -> Map.put(acc, item, true) end)
        end
      end
      """

      assert fix(code) == code
    end
  end

  describe "round-trip: fixed code has no further issues" do
    test "identity and derived both settle in one pass" do
      identity = """
      defmodule Bad do
        def count(list) do
          Enum.reduce(list, %{}, fn item, acc -> Map.update(acc, item, 1, &(&1 + 1)) end)
        end
      end
      """

      derived = """
      defmodule Bad do
        def count(words) do
          Enum.reduce(words, %{}, fn word, acc -> Map.update(acc, String.downcase(word), 1, &(&1 + 1)) end)
        end
      end
      """

      assert check(fix(identity)) == []
      assert check(fix(derived)) == []
    end
  end

  # ── behaviour preservation ─────────────────────────────────────────
  # The strongest guarantee: run the original and fixed code over input sets
  # and assert the resulting maps are element-for-element identical.

  defp eval1(expr) do
    {f, _} = Code.eval_string("fn list -> #{expr} end")
    f
  end

  defp assert_preserves(reduce_expr, inputs) do
    assert check(reduce_expr) != [], "expected the rule to fire on: #{reduce_expr}"

    fixed = fix(reduce_expr)
    assert fixed != reduce_expr, "expected the rule to rewrite the reduce:\n#{fixed}"

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
end
