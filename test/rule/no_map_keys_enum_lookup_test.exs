defmodule Credence.Pattern.NoMapKeysEnumLookupTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoMapKeysEnumLookup.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoMapKeysEnumLookup.fix(code, [])
  end

  defp assert_fixes_cleanly(code) do
    fixed = fix(code)

    assert {:ok, ast} = Code.string_to_quoted(fixed),
           "Expected fixed code to parse as valid Elixir:\n#{fixed}"

    assert [] == Credence.Pattern.NoMapKeysEnumLookup.check(ast, []),
           "Expected no remaining issues in fixed code:\n#{fixed}"

    fixed
  end

  describe "NoMapKeysEnumLookup — check" do
    # ---- Pipeline form: Map.keys(var) |> Enum.xxx(fn ... var[k] ...) ----

    test "detects Map.keys |> Enum.all? with access syntax lookup" do
      code = """
      defmodule Bad do
        def check(word_freqs, letter_freqs) do
          Map.keys(word_freqs)
          |> Enum.all?(fn char ->
            Map.get(letter_freqs, char, 0) >= word_freqs[char]
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_keys_enum_lookup
      assert issue.message =~ "word_freqs"
      assert issue.message =~ "Enum.all?"
    end

    test "detects Map.keys |> Enum.map with Map.get lookup" do
      code = """
      defmodule Bad do
        def transform(counts) do
          Map.keys(counts)
          |> Enum.map(fn k -> {k, Map.get(counts, k, 0) * 2} end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "counts"
      assert issue.message =~ "Enum.map"
    end

    test "detects Map.keys |> Enum.filter with Map.fetch! lookup" do
      code = """
      defmodule Bad do
        def big_values(data) do
          Map.keys(data)
          |> Enum.filter(fn k -> Map.fetch!(data, k) > 100 end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "data"
      assert issue.message =~ "Enum.filter"
    end

    test "detects Map.keys |> Enum.any? with access lookup" do
      code = """
      defmodule Bad do
        def has_nil?(config) do
          Map.keys(config)
          |> Enum.any?(fn k -> config[k] == nil end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "config"
      assert issue.message =~ "Enum.any?"
    end

    test "detects Map.keys |> Enum.each with access lookup" do
      code = """
      defmodule Bad do
        def print_all(scores) do
          Map.keys(scores)
          |> Enum.each(fn k -> IO.puts(scores[k]) end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "scores"
      assert issue.message =~ "Enum.each"
    end

    test "detects Map.keys |> Enum.reject with access lookup" do
      code = """
      defmodule Bad do
        def remove_zeros(freq) do
          Map.keys(freq)
          |> Enum.reject(fn k -> freq[k] == 0 end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "freq"
    end

    test "detects Map.keys |> Enum.flat_map with access lookup" do
      code = """
      defmodule Bad do
        def expand(groups) do
          Map.keys(groups)
          |> Enum.flat_map(fn k -> groups[k] end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "groups"
    end

    # ---- Three-step pipeline: var |> Map.keys() |> Enum.xxx(fn ...) ----

    test "detects var |> Map.keys() |> Enum.all? with lookup" do
      code = """
      defmodule Bad do
        def check(freqs, other) do
          freqs
          |> Map.keys()
          |> Enum.all?(fn k -> other[k] >= freqs[k] end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "freqs"
    end

    # ---- Direct call form: Enum.xxx(Map.keys(var), fn ...) ----

    test "detects direct call Enum.all?(Map.keys(var), fn ...)" do
      code = """
      defmodule Bad do
        def valid?(word_freqs, letter_freqs) do
          Enum.all?(Map.keys(word_freqs), fn char ->
            Map.get(letter_freqs, char, 0) >= word_freqs[char]
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "word_freqs"
      assert issue.message =~ "Enum.all?"
    end

    test "detects direct call Enum.map(Map.keys(var), fn ...)" do
      code = """
      defmodule Bad do
        def pairs(m) do
          Enum.map(Map.keys(m), fn k -> {k, Map.get(m, k)} end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.map"
    end

    # ---- Negative cases ----

    test "does not flag Map.keys |> Enum.sort (no callback lookup)" do
      code = """
      defmodule Good do
        def sorted_keys(config) do
          Map.keys(config) |> Enum.sort()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.keys |> Enum.join (not a flagged function)" do
      code = """
      defmodule Good do
        def key_string(config) do
          Map.keys(config) |> Enum.join(", ")
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.keys when callback doesn't reference source map" do
      code = """
      defmodule Good do
        def check_keys(freqs) do
          Map.keys(freqs)
          |> Enum.all?(fn k -> is_atom(k) end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.keys when callback references a different map" do
      code = """
      defmodule Good do
        def lookup(source, target) do
          Map.keys(source)
          |> Enum.map(fn k -> target[k] end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag direct map iteration (correct pattern)" do
      code = """
      defmodule Good do
        def check(word_freqs, letter_freqs) do
          Enum.all?(word_freqs, fn {char, count} ->
            Map.get(letter_freqs, char, 0) >= count
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.keys with Enum.count (not flagged)" do
      code = """
      defmodule Good do
        def size(m), do: Map.keys(m) |> Enum.count()
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.keys stored in a variable" do
      code = """
      defmodule Good do
        def process(m) do
          keys = Map.keys(m)
          Enum.map(keys, fn k -> m[k] end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag non-Map module keys function" do
      code = """
      defmodule Good do
        def foo(m) do
          MyModule.keys(m) |> Enum.map(fn k -> m[k] end)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "NoMapKeysEnumLookup — fix (value-returning Enum functions)" do
    test "fixes Map.keys |> Enum.all? with access syntax" do
      code = """
      Map.keys(word_freqs) |> Enum.all?(fn char -> Map.get(letter_freqs, char, 0) >= word_freqs[char] end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.all?"
      assert fixed =~ "word_freqs"
      assert fixed =~ "{char, v}"
      assert fixed =~ ">= v"
      refute fixed =~ "Map.keys"
      refute fixed =~ "word_freqs[char]"
    end

    test "fixes Map.keys |> Enum.map with Map.get(var, key, default)" do
      code = """
      Map.keys(counts) |> Enum.map(fn k -> {k, Map.get(counts, k, 0) * 2} end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.map(counts"
      assert fixed =~ "{k, v}"
      assert fixed =~ "v * 2"
      refute fixed =~ "Map.keys"
      refute fixed =~ "Map.get(counts"
    end

    test "fixes Map.keys |> Enum.any? with access lookup" do
      code = """
      Map.keys(config) |> Enum.any?(fn k -> config[k] == nil end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.any?(config"
      assert fixed =~ "v == nil"
      refute fixed =~ "Map.keys"
    end

    test "fixes Map.keys |> Enum.each with access lookup" do
      code = """
      Map.keys(scores) |> Enum.each(fn k -> IO.puts(scores[k]) end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.each(scores"
      assert fixed =~ "IO.puts(v)"
      refute fixed =~ "Map.keys"
    end

    test "fixes Map.keys |> Enum.flat_map with access lookup" do
      code = """
      Map.keys(groups) |> Enum.flat_map(fn k -> groups[k] end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.flat_map(groups"
      assert fixed =~ "{k, v} ->"
      assert fixed =~ "-> v"
      refute fixed =~ "Map.keys"
      refute fixed =~ "groups[k]"
    end

    test "fixes Map.keys |> Enum.all? with Map.fetch! lookup" do
      code = """
      Map.keys(data) |> Enum.all?(fn k -> Map.fetch!(data, k) > 0 end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.all?(data"
      assert fixed =~ "v > 0"
      refute fixed =~ "Map.keys"
      refute fixed =~ "Map.fetch!"
    end

    test "fixes Map.keys |> Enum.map with Map.fetch lookup (returns {:ok, v})" do
      code = """
      Map.keys(data) |> Enum.map(fn k -> {k, Map.fetch(data, k)} end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.map(data"
      assert fixed =~ "{k, v}"
      assert fixed =~ "{:ok, v}"
      refute fixed =~ "Map.keys"
      refute fixed =~ "Map.fetch(data"
    end

    test "fixes callback with guard" do
      code = """
      Map.keys(m) |> Enum.map(fn k when is_atom(k) -> {k, m[k]} end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "{k, v}"
      assert fixed =~ "is_atom(k)"
      # the value v replaces m[k]
      assert fixed =~ "{k, v}"
      refute fixed =~ "Map.keys"
    end

    test "fixes longer pipeline after Map.keys |> Enum.map" do
      code = """
      Map.keys(counts)
      |> Enum.map(fn k -> {k, Map.get(counts, k, 0) * 2} end)
      |> Enum.sort()
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.map"
      assert fixed =~ "counts"
      assert fixed =~ "v * 2"
      assert fixed =~ "Enum.sort()"
      refute fixed =~ "Map.keys"
      refute fixed =~ "Map.get(counts"
    end

    test "preserves non-lookup references to the map variable" do
      code = """
      Map.keys(m) |> Enum.map(fn k -> {k, m[k], map_size(m)} end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "map_size(m)"
      assert fixed =~ "{k, v,"
      refute fixed =~ "Map.keys"
    end

    test "only replaces lookups with matching key variable" do
      code = """
      Map.keys(m) |> Enum.map(fn k -> m[k] + m[:default] end)
      """

      fixed = assert_fixes_cleanly(code)
      # m[k] replaced with v, m[:default] left as-is
      assert fixed =~ "v + m[:default]"
      refute fixed =~ "Map.keys"
    end
  end

  describe "NoMapKeysEnumLookup — fix (three-step pipeline)" do
    test "fixes var |> Map.keys() |> Enum.all? with lookup" do
      code = """
      freqs |> Map.keys() |> Enum.all?(fn k -> other[k] >= freqs[k] end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "freqs |> Enum.all?"
      assert fixed =~ ">= v"
      refute fixed =~ "Map.keys"
    end

    test "fixes var |> Map.keys() |> Enum.map with Map.get" do
      code = """
      counts |> Map.keys() |> Enum.map(fn k -> {k, Map.get(counts, k, 0)} end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "counts |> Enum.map"
      assert fixed =~ "{k, v}"
      refute fixed =~ "Map.keys"
    end

    test "fixes three-step with longer pipeline" do
      code = """
      freqs
      |> Map.keys()
      |> Enum.map(fn k -> {k, freqs[k]} end)
      |> Enum.sort()
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "freqs"
      assert fixed =~ "Enum.map"
      assert fixed =~ "Enum.sort()"
      refute fixed =~ "Map.keys"
    end
  end

  describe "NoMapKeysEnumLookup — fix (direct call form)" do
    test "fixes Enum.all?(Map.keys(var), callback)" do
      code = """
      Enum.all?(Map.keys(word_freqs), fn char -> Map.get(letter_freqs, char, 0) >= word_freqs[char] end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.all?(word_freqs"
      assert fixed =~ "{char, v}"
      assert fixed =~ ">= v"
      refute fixed =~ "Map.keys"
    end

    test "fixes Enum.map(Map.keys(var), callback)" do
      code = """
      Enum.map(Map.keys(m), fn k -> {k, Map.get(m, k)} end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.map(m"
      assert fixed =~ "{k, v}"
      refute fixed =~ "Map.keys"
    end
  end

  describe "NoMapKeysEnumLookup — fix (keys-returning Enum functions)" do
    test "fixes Map.keys |> Enum.filter (adds Enum.map to extract keys)" do
      code = """
      Map.keys(data) |> Enum.filter(fn k -> Map.fetch!(data, k) > 100 end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.filter(data"
      assert fixed =~ "v > 100"
      assert fixed =~ "Enum.map"
      assert fixed =~ "{k, _v}"
      refute fixed =~ "Map.keys"
      refute fixed =~ "Map.fetch!"
    end

    test "fixes Map.keys |> Enum.reject (adds Enum.map to extract keys)" do
      code = """
      Map.keys(freq) |> Enum.reject(fn k -> freq[k] == 0 end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.reject(freq"
      assert fixed =~ "v == 0"
      assert fixed =~ "Enum.map"
      assert fixed =~ "{k, _v}"
      refute fixed =~ "Map.keys"
    end

    test "fixes three-step with Enum.filter" do
      code = """
      data |> Map.keys() |> Enum.filter(fn k -> data[k] > 100 end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "data |> Enum.filter"
      assert fixed =~ "v > 100"
      assert fixed =~ "Enum.map"
      refute fixed =~ "Map.keys"
    end

    test "fixes direct call Enum.filter(Map.keys(var), callback)" do
      code = """
      Enum.filter(Map.keys(data), fn k -> Map.fetch!(data, k) > 100 end)
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.filter(data"
      assert fixed =~ "Enum.map"
      refute fixed =~ "Map.keys"
    end

    test "fixes Enum.filter with pipeline continuation" do
      code = """
      Map.keys(data) |> Enum.filter(fn k -> data[k] > 100 end) |> Enum.sort()
      """

      fixed = assert_fixes_cleanly(code)
      assert fixed =~ "Enum.filter(data"
      assert fixed =~ "Enum.map"
      assert fixed =~ "Enum.sort()"
      refute fixed =~ "Map.keys"
    end
  end

  describe "NoMapKeysEnumLookup — fix (multiple lookups)" do
    test "replaces multiple lookup patterns in the same callback" do
      code = """
      Map.keys(m) |> Enum.map(fn k -> m[k] + Map.get(m, k, 0) end)
      """

      fixed = assert_fixes_cleanly(code)
      # Both lookups should be replaced with v
      assert fixed =~ "v + v"
      refute fixed =~ "Map.keys"
      refute fixed =~ "Map.get(m"
      refute fixed =~ "m[k]"
    end

    test "replaces access but leaves Map.fetch for different key expressions" do
      code = """
      Map.keys(m) |> Enum.map(fn k -> m[k] + m[k + 1] end)
      """

      fixed = assert_fixes_cleanly(code)
      # m[k] replaced with v, m[k + 1] left as-is
      assert fixed =~ "v + m[k + 1]"
      refute fixed =~ "Map.keys"
    end
  end

  describe "NoMapKeysEnumLookup — fix (negative / passthrough)" do
    test "returns source unchanged when no pattern is detected" do
      code = """
      Map.keys(config) |> Enum.sort()
      """

      fixed = fix(code)
      {:ok, _} = Code.string_to_quoted(fixed)
      # Should still contain Map.keys since the pattern wasn't flagged
      assert fixed =~ "Map.keys"
    end

    test "returns source unchanged for multi-clause callback" do
      code = """
      Map.keys(m)
      |> Enum.map(fn
        k when is_binary(k) -> {k, m[k]}
        k -> {k, m[k]}
      end)
      """

      # Multi-clause callbacks are not transformed — node is left as-is
      fixed = fix(code)
      {:ok, _} = Code.string_to_quoted(fixed)
      assert fixed =~ "Map.keys"
    end
  end
end
