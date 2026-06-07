defmodule Credence.Pattern.NoManualFrequenciesFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualFrequencies

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

      assert fix(NoManualFrequencies, code) == expected
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

      assert fix(NoManualFrequencies, code) == expected
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

      assert fix(NoManualFrequencies, code) == expected
    end

    test "non-frequency reduce is left unchanged" do
      code = """
      defmodule Safe do
        def group(list) do
          Enum.reduce(list, %{}, fn item, acc -> Map.put(acc, item, true) end)
        end
      end
      """

      assert fix(NoManualFrequencies, code) == code
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

      assert check(NoManualFrequencies, fix(NoManualFrequencies, identity)) == []
      assert check(NoManualFrequencies, fix(NoManualFrequencies, derived)) == []
    end
  end

  # Behaviour preservation (run original vs fixed over input sets) lives in
  # no_manual_frequencies_equivalence_test.exs via `assert_equivalent`.
end
