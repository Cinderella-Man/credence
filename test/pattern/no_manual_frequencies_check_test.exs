defmodule Credence.Pattern.NoManualFrequenciesCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoManualFrequencies

  describe "fires on the safe frequency-counting shapes" do
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

      issues = check(NoManualFrequencies, code)
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

      assert length(check(NoManualFrequencies, code)) == 1
    end

    test "derived key (String.downcase)" do
      code = """
      Enum.reduce(words, %{}, fn word, acc ->
        Map.update(acc, String.downcase(word), 1, &(&1 + 1))
      end)
      """

      assert length(check(NoManualFrequencies, code)) == 1
    end

    test "fn-form increment (fn n -> n + 1 end)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update(acc, item, 1, fn n -> n + 1 end)
      end)
      """

      assert length(check(NoManualFrequencies, code)) == 1
    end
  end

  describe "does NOT fire (no safe same-answer rewrite)" do
    test "already uses Enum.frequencies/1" do
      code = """
      string |> String.graphemes() |> Enum.frequencies()
      """

      assert check(NoManualFrequencies, code) == []
    end

    test "non-empty initial accumulator" do
      code = """
      Enum.reduce(list, initial, fn item, acc ->
        Map.update(acc, item, 1, &(&1 + 1))
      end)
      """

      assert check(NoManualFrequencies, code) == []
    end

    test "no Map.update (Map.put)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.put(acc, item, true)
      end)
      """

      assert check(NoManualFrequencies, code) == []
    end

    test "group-by pattern (list default, not a count)" do
      code = """
      Enum.reduce(words, %{}, fn word, acc ->
        Map.update(acc, String.first(word), [word], fn existing -> [word | existing] end)
      end)
      """

      assert check(NoManualFrequencies, code) == []
    end

    test "non-1 default" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update(acc, item, 0, &(&1 + 1))
      end)
      """

      assert check(NoManualFrequencies, code) == []
    end

    test "weighted increment (+2 is not a plain count)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update(acc, item, 1, &(&1 + 2))
      end)
      """

      assert check(NoManualFrequencies, code) == []
    end

    test "Map.update! variant (raises on the first, missing key)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update!(acc, item, &(&1 + 1))
      end)
      """

      assert check(NoManualFrequencies, code) == []
    end

    test "key references the accumulator (can't extract to a key function)" do
      code = """
      Enum.reduce(list, %{}, fn item, acc ->
        Map.update(acc, map_size(acc), 1, &(&1 + 1))
      end)
      """

      assert check(NoManualFrequencies, code) == []
    end
  end
end
