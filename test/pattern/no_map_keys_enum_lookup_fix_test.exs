defmodule Credence.Pattern.NoMapKeysEnumLookupFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMapKeysEnumLookup

  describe "fix (boolean Enum functions — all?/any?)" do
    test "fixes Map.keys |> Enum.all? with access syntax" do
      input =
        "Map.keys(word_freqs) |> Enum.all?(fn char -> Map.get(letter_freqs, char, 0) >= word_freqs[char] end)"

      expected = "Enum.all?(word_freqs, fn {char, v} -> Map.get(letter_freqs, char, 0) >= v end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "fixes Map.keys |> Enum.any? with access lookup" do
      input = "Map.keys(config) |> Enum.any?(fn k -> config[k] == nil end)"

      expected = "Enum.any?(config, fn {k, v} -> v == nil end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "fixes Map.keys |> Enum.all? with Map.get(var, key, default)" do
      input = "Map.keys(counts) |> Enum.all?(fn k -> Map.get(counts, k, 0) > 2 end)"

      expected = "Enum.all?(counts, fn {k, v} -> v > 2 end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "fixes Map.keys |> Enum.all? with Map.fetch! lookup" do
      input = "Map.keys(data) |> Enum.all?(fn k -> Map.fetch!(data, k) > 0 end)"

      expected = "Enum.all?(data, fn {k, v} -> v > 0 end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "fixes Map.keys |> Enum.all? with Map.fetch lookup (returns {:ok, v})" do
      input = "Map.keys(data) |> Enum.all?(fn k -> match?({:ok, _}, Map.fetch(data, k)) end)"

      expected = "Enum.all?(data, fn {k, v} -> match?({:ok, _}, {:ok, v}) end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "fixes callback with guard" do
      input = "Map.keys(m) |> Enum.all?(fn k when is_atom(k) -> m[k] end)"

      expected = "Enum.all?(m, fn {k, v} when is_atom(k) -> v end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "fixes longer pipeline after Map.keys |> Enum.all?" do
      input = """
      Map.keys(counts)
      |> Enum.all?(fn k -> Map.get(counts, k, 0) > 0 end)
      |> Kernel.and(true)
      """

      expected = """
      Enum.all?(counts, fn {k, v} -> v > 0 end)
      |> Kernel.and(true)
      """

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "preserves non-lookup references to the map variable" do
      input = "Map.keys(m) |> Enum.all?(fn k -> m[k] and map_size(m) > 0 end)"

      expected = "Enum.all?(m, fn {k, v} -> v and map_size(m) > 0 end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "only replaces lookups with matching key variable" do
      input = "Map.keys(m) |> Enum.all?(fn k -> m[k] and m[:default] end)"

      expected = "Enum.all?(m, fn {k, v} -> v and m[:default] end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end
  end

  describe "fix (three-step pipeline)" do
    test "fixes var |> Map.keys() |> Enum.all? with lookup" do
      input = "freqs |> Map.keys() |> Enum.all?(fn k -> other[k] >= freqs[k] end)"

      expected = "freqs |> Enum.all?(fn {k, v} -> other[k] >= v end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "fixes var |> Map.keys() |> Enum.any? with Map.get" do
      input = "counts |> Map.keys() |> Enum.any?(fn k -> Map.get(counts, k, 0) > 0 end)"

      expected = "counts |> Enum.any?(fn {k, v} -> v > 0 end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end
  end

  describe "fix (direct call form)" do
    test "fixes Enum.all?(Map.keys(var), callback)" do
      input =
        "Enum.all?(Map.keys(word_freqs), fn char -> Map.get(letter_freqs, char, 0) >= word_freqs[char] end)"

      expected = "Enum.all?(word_freqs, fn {char, v} -> Map.get(letter_freqs, char, 0) >= v end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "fixes Enum.any?(Map.keys(var), callback)" do
      input = "Enum.any?(Map.keys(m), fn k -> Map.get(m, k) == nil end)"

      expected = "Enum.any?(m, fn {k, v} -> v == nil end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end
  end

  describe "fix (multiple lookups)" do
    test "replaces multiple lookup patterns in the same callback" do
      input = "Map.keys(m) |> Enum.all?(fn k -> m[k] || Map.get(m, k, 0) end)"

      expected = "Enum.all?(m, fn {k, v} -> v || v end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end

    test "replaces access but leaves lookups for different key expressions" do
      input = "Map.keys(m) |> Enum.all?(fn k -> m[k] or m[k + 1] end)"

      expected = "Enum.all?(m, fn {k, v} -> v or m[k + 1] end)"

      confirm_fix(fix(NoMapKeysEnumLookup, input), expected)
    end
  end

  # ---- NOT fixed: order-observable sinks (narrowed away → no-op) ----

  describe "fix (order-observable sinks are no-ops)" do
    test "leaves Map.keys |> Enum.map unchanged" do
      code = "Map.keys(counts) |> Enum.map(fn k -> {k, Map.get(counts, k, 0) * 2} end)"

      confirm_fix(fix(NoMapKeysEnumLookup, code), code)
    end

    test "leaves Map.keys |> Enum.filter unchanged" do
      code = "Map.keys(data) |> Enum.filter(fn k -> Map.fetch!(data, k) > 100 end)"

      confirm_fix(fix(NoMapKeysEnumLookup, code), code)
    end

    test "leaves Map.keys |> Enum.reject unchanged" do
      code = "Map.keys(freq) |> Enum.reject(fn k -> freq[k] == 0 end)"

      confirm_fix(fix(NoMapKeysEnumLookup, code), code)
    end

    test "leaves Map.keys |> Enum.flat_map unchanged" do
      code = "Map.keys(groups) |> Enum.flat_map(fn k -> groups[k] end)"

      confirm_fix(fix(NoMapKeysEnumLookup, code), code)
    end

    test "leaves Map.keys |> Enum.each unchanged" do
      code = "Map.keys(scores) |> Enum.each(fn k -> IO.puts(scores[k]) end)"

      confirm_fix(fix(NoMapKeysEnumLookup, code), code)
    end

    test "leaves direct call Enum.map(Map.keys(var), callback) unchanged" do
      code = "Enum.map(Map.keys(m), fn k -> {k, Map.get(m, k)} end)"

      confirm_fix(fix(NoMapKeysEnumLookup, code), code)
    end
  end

  describe "fix (negative / passthrough)" do
    test "returns source unchanged when no pattern is detected" do
      code = "Map.keys(config) |> Enum.sort()"

      confirm_fix(fix(NoMapKeysEnumLookup, code), code)
    end

    test "returns source unchanged for multi-clause callback" do
      code = """
      Map.keys(m)
      |> Enum.all?(fn
        k when is_binary(k) -> m[k]
        k -> m[k]
      end)
      """

      confirm_fix(fix(NoMapKeysEnumLookup, code), code)
    end
  end
end
