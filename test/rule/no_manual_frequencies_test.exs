defmodule Credence.Pattern.NoManualFrequenciesTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoManualFrequencies.check(ast, [])
  end

  defp fix(code), do: Credence.Pattern.NoManualFrequencies.fix(code, [])

  describe "fixable?" do
    test "reports as fixable" do
      assert Credence.Pattern.NoManualFrequencies.fixable?() == true
    end
  end

  describe "NoManualFrequencies" do
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
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Pattern.NoManualFrequencies.check(ast, []) == []
    end
  end
end
