defmodule Credence.Pattern.NoManualFrequenciesTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoManualFrequencies

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualFrequencies.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoManualFrequencies, code, [])

  describe "NoManualFrequencies" do
    test "detects derived-key frequency counting (Enum.frequencies_by)" do
      code = """
      defmodule NotFreq do
        def count_substrings(s, min_size) do
          limit = String.length(s) - min_size

          Enum.reduce(0..limit, %{}, fn start, freq_map ->
            substring = String.slice(s, start, min_size)
            Map.update(freq_map, substring, 1, &(&1 + 1))
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_manual_frequencies
      assert hd(issues).message =~ "Enum.frequencies_by"
    end

    test "passes when reduce has conditional Map.update" do
      code = """
      defmodule FilteredFreq do
        def count_valid(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            if valid?(x) do
              Map.update(acc, x, 1, &(&1 + 1))
            else
              acc
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code using Enum.frequencies/1" do
      code = """
      defmodule Good do
        def char_freq(string) do
          string |> String.graphemes() |> Enum.frequencies()
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.reduce with non-empty initial map" do
      code = """
      defmodule Safe do
        def count_with_defaults(list, initial) do
          Enum.reduce(list, initial, fn item, acc ->
            Map.update(acc, item, 1, &(&1 + 1))
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.reduce with %{} but no Map.update" do
      code = """
      defmodule Safe do
        def group(list) do
          Enum.reduce(list, %{}, fn item, acc ->
            Map.put(acc, item, true)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes group-by pattern using Map.update with list default" do
      code = """
      defmodule IndexByFirstLetter do
        def build(words) do
          Enum.reduce(words, %{}, fn word, acc ->
            first = String.first(word)

            Map.update(acc, first, [word], fn existing ->
              [word | existing]
            end)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.reduce with %{} and Map.update" do
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
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_manual_frequencies

      assert issue.message =~ "Enum.frequencies"
      assert issue.meta.line != nil
    end

    test "detects non-piped Enum.reduce with Map.update" do
      code = """
      defmodule Bad do
        def word_count(words) do
          Enum.reduce(words, %{}, fn word, acc ->
            Map.update(acc, word, 1, &(&1 + 1))
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_manual_frequencies
    end

    test "detects Map.update! variant" do
      code = """
      defmodule Bad do
        def count(list) do
          Enum.reduce(list, %{}, fn item, acc ->
            Map.update!(acc, item, &(&1 + 1))
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "detects piped derived-key frequency counting" do
      code = """
      defmodule DerivedKey do
        def count_by_transform(list) do
          list
          |> Enum.reduce(%{}, fn item, acc ->
            key = transform(item)
            Map.update(acc, key, 1, &(&1 + 1))
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "Enum.frequencies_by"
    end

    test "passes when derived-key reduce has conditional" do
      code = """
      defmodule FilteredDerived do
        def count(list) do
          Enum.reduce(list, %{}, fn item, acc ->
            key = transform(item)

            if valid?(key) do
              Map.update(acc, key, 1, &(&1 + 1))
            else
              acc
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes when body has more than two expressions" do
      code = """
      defmodule MultiExpr do
        def count(list) do
          Enum.reduce(list, %{}, fn item, acc ->
            key = transform(item)
            IO.puts(key)
            Map.update(acc, key, 1, &(&1 + 1))
          end)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces direct reduce with Enum.frequencies/1" do
      code = """
      Enum.reduce(list, %{}, fn item, counts ->
        Map.update(counts, item, 1, &(&1 + 1))
      end)
      """

      result = fix(code)
      assert result =~ "Enum.frequencies(list)"
      refute result =~ "Enum.reduce"
    end

    test "replaces piped reduce with Enum.frequencies/1" do
      code = """
      list |> Enum.reduce(%{}, fn item, counts ->
        Map.update(counts, item, 1, &(&1 + 1))
      end)
      """

      result = fix(code)
      assert result =~ "Enum.frequencies(list)"
      refute result =~ "Enum.reduce"
    end

    test "does not modify non-frequency reductions" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.put(acc, item, true)
      end)
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      refute result =~ "Enum.frequencies"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def count(list) do
          total = length(list)
          freqs = Enum.reduce(list, %{}, fn item, acc ->
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

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(list, %{}, fn item, counts ->
        Map.update(counts, item, 1, &(&1 + 1))
      end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoManualFrequencies.check(ast, []) == []
    end

    test "replaces derived-key reduce with Enum.frequencies_by" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        key = transform(item)
        Map.update(acc, key, 1, &(&1 + 1))
      end)
      """

      result = fix(code)
      assert result =~ "Enum.frequencies_by"
      assert result =~ "fn item -> transform(item) end"
      refute result =~ "Enum.reduce"
    end

    test "replaces piped derived-key reduce with Enum.frequencies_by" do
      code = """
      list |> Enum.reduce(%{}, fn item, acc ->
        key = transform(item)
        Map.update(acc, key, 1, &(&1 + 1))
      end)
      """

      result = fix(code)
      assert result =~ "Enum.frequencies_by"
      assert result =~ "fn item -> transform(item) end"
      refute result =~ "Enum.reduce"
    end

    test "round-trip: derived-key fix produces no issues" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        key = transform(item)
        Map.update(acc, key, 1, &(&1 + 1))
      end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoManualFrequencies.check(ast, []) == []
    end

    test "replaces derived-key reduce with pipe expression" do
      code = """
      1..n |> Enum.reduce(%{}, fn num, acc ->
        digit_sum = num |> Integer.digits() |> Enum.sum()
        Map.update(acc, digit_sum, 1, &(&1 + 1))
      end)
      """

      result = fix(code)
      assert result =~ "Enum.frequencies_by"
      assert result =~ "Integer.digits"
      assert result =~ "Enum.sum"
      refute result =~ "Enum.reduce"
    end
  end
end
