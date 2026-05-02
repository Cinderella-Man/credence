defmodule Credence.Rule.NoMapKeysEnumLookupTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoMapKeysEnumLookup.check(ast, [])
  end

  describe "NoMapKeysEnumLookup" do
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
end
