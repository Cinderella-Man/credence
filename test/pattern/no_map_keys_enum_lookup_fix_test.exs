defmodule Credence.Pattern.NoMapKeysEnumLookupFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMapKeysEnumLookup

  describe "fix (value-returning Enum functions)" do
    test "fixes Map.keys |> Enum.all? with access syntax" do
      input = """
      Map.keys(word_freqs) |> Enum.all?(fn char -> Map.get(letter_freqs, char, 0) >= word_freqs[char] end)
      """

      expected = """
      Enum.all?(word_freqs, fn {char, v} -> Map.get(letter_freqs, char, 0) >= v end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes Map.keys |> Enum.map with Map.get(var, key, default)" do
      input = """
      Map.keys(counts) |> Enum.map(fn k -> {k, Map.get(counts, k, 0) * 2} end)
      """

      expected = """
      Enum.map(counts, fn {k, v} -> {k, v * 2} end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes Map.keys |> Enum.any? with access lookup" do
      input = """
      Map.keys(config) |> Enum.any?(fn k -> config[k] == nil end)
      """

      expected = """
      Enum.any?(config, fn {k, v} -> v == nil end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes Map.keys |> Enum.each with access lookup" do
      input = """
      Map.keys(scores) |> Enum.each(fn k -> IO.puts(scores[k]) end)
      """

      expected = """
      Enum.each(scores, fn {k, v} -> IO.puts(v) end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes Map.keys |> Enum.flat_map with access lookup" do
      input = """
      Map.keys(groups) |> Enum.flat_map(fn k -> groups[k] end)
      """

      expected = """
      Enum.flat_map(groups, fn {k, v} -> v end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes Map.keys |> Enum.all? with Map.fetch! lookup" do
      input = """
      Map.keys(data) |> Enum.all?(fn k -> Map.fetch!(data, k) > 0 end)
      """

      expected = """
      Enum.all?(data, fn {k, v} -> v > 0 end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes Map.keys |> Enum.map with Map.fetch lookup (returns {:ok, v})" do
      input = """
      Map.keys(data) |> Enum.map(fn k -> {k, Map.fetch(data, k)} end)
      """

      expected = """
      Enum.map(data, fn {k, v} -> {k, {:ok, v}} end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes callback with guard" do
      input = """
      Map.keys(m) |> Enum.map(fn k when is_atom(k) -> {k, m[k]} end)
      """

      expected = """
      Enum.map(m, fn {k, v} when is_atom(k) -> {k, v} end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes longer pipeline after Map.keys |> Enum.map" do
      input = """
      Map.keys(counts)
      |> Enum.map(fn k -> {k, Map.get(counts, k, 0) * 2} end)
      |> Enum.sort()
      """

      expected = """
      Enum.map(counts, fn {k, v} -> {k, v * 2} end)
      |> Enum.sort()
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "preserves non-lookup references to the map variable" do
      input = """
      Map.keys(m) |> Enum.map(fn k -> {k, m[k], map_size(m)} end)
      """

      expected = """
      Enum.map(m, fn {k, v} -> {k, v, map_size(m)} end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "only replaces lookups with matching key variable" do
      input = """
      Map.keys(m) |> Enum.map(fn k -> m[k] + m[:default] end)
      """

      expected = """
      Enum.map(m, fn {k, v} -> v + m[:default] end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end
  end

  describe "fix (three-step pipeline)" do
    test "fixes var |> Map.keys() |> Enum.all? with lookup" do
      input = """
      freqs |> Map.keys() |> Enum.all?(fn k -> other[k] >= freqs[k] end)
      """

      expected = """
      freqs |> Enum.all?(fn {k, v} -> other[k] >= v end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes var |> Map.keys() |> Enum.map with Map.get" do
      input = """
      counts |> Map.keys() |> Enum.map(fn k -> {k, Map.get(counts, k, 0)} end)
      """

      expected = """
      counts |> Enum.map(fn {k, v} -> {k, v} end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes three-step with longer pipeline" do
      input = """
      freqs
      |> Map.keys()
      |> Enum.map(fn k -> {k, freqs[k]} end)
      |> Enum.sort()
      """

      expected = """
      freqs
      |> Enum.map(fn {k, v} -> {k, v} end)
      |> Enum.sort()
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end
  end

  describe "fix (direct call form)" do
    test "fixes Enum.all?(Map.keys(var), callback)" do
      input = """
      Enum.all?(Map.keys(word_freqs), fn char -> Map.get(letter_freqs, char, 0) >= word_freqs[char] end)
      """

      expected = """
      Enum.all?(word_freqs, fn {char, v} -> Map.get(letter_freqs, char, 0) >= v end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes Enum.map(Map.keys(var), callback)" do
      input = """
      Enum.map(Map.keys(m), fn k -> {k, Map.get(m, k)} end)
      """

      expected = """
      Enum.map(m, fn {k, v} -> {k, v} end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end
  end

  describe "fix (keys-returning Enum functions)" do
    test "fixes Map.keys |> Enum.filter (adds Enum.map to extract keys)" do
      input = """
      Map.keys(data) |> Enum.filter(fn k -> Map.fetch!(data, k) > 100 end)
      """

      expected = """
      Enum.filter(data, fn {k, v} -> v > 100 end) |> Enum.map(fn {k, _v} -> k end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes Map.keys |> Enum.reject (adds Enum.map to extract keys)" do
      input = """
      Map.keys(freq) |> Enum.reject(fn k -> freq[k] == 0 end)
      """

      expected = """
      Enum.reject(freq, fn {k, v} -> v == 0 end) |> Enum.map(fn {k, _v} -> k end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes three-step with Enum.filter" do
      input = """
      data |> Map.keys() |> Enum.filter(fn k -> data[k] > 100 end)
      """

      expected = """
      data |> Enum.filter(fn {k, v} -> v > 100 end) |> Enum.map(fn {k, _v} -> k end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes direct call Enum.filter(Map.keys(var), callback)" do
      input = """
      Enum.filter(Map.keys(data), fn k -> Map.fetch!(data, k) > 100 end)
      """

      expected = """
      Enum.filter(data, fn {k, v} -> v > 100 end) |> Enum.map(fn {k, _v} -> k end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "fixes Enum.filter with pipeline continuation" do
      input = """
      Map.keys(data) |> Enum.filter(fn k -> data[k] > 100 end) |> Enum.sort()
      """

      expected = """
      Enum.filter(data, fn {k, v} -> v > 100 end) |> Enum.map(fn {k, _v} -> k end) |> Enum.sort()
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end
  end

  describe "fix (multiple lookups)" do
    test "replaces multiple lookup patterns in the same callback" do
      input = """
      Map.keys(m) |> Enum.map(fn k -> m[k] + Map.get(m, k, 0) end)
      """

      expected = """
      Enum.map(m, fn {k, v} -> v + v end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end

    test "replaces access but leaves Map.fetch for different key expressions" do
      input = """
      Map.keys(m) |> Enum.map(fn k -> m[k] + m[k + 1] end)
      """

      expected = """
      Enum.map(m, fn {k, v} -> v + m[k + 1] end)
      """

      assert fix(NoMapKeysEnumLookup, input) == expected
    end
  end

  describe "fix (negative / passthrough)" do
    test "returns source unchanged when no pattern is detected" do
      code = """
      Map.keys(config) |> Enum.sort()
      """

      assert fix(NoMapKeysEnumLookup, code) == code
    end

    test "returns source unchanged for multi-clause callback" do
      code = """
      Map.keys(m)
      |> Enum.map(fn
        k when is_binary(k) -> {k, m[k]}
        k -> {k, m[k]}
      end)
      """

      assert fix(NoMapKeysEnumLookup, code) == code
    end
  end
end
