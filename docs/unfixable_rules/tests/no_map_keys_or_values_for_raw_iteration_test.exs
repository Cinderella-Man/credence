defmodule Credence.Pattern.NoMapKeysOrValuesForRawIterationTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoMapKeysOrValuesForRawIteration.check(ast, [])
  end

  describe "NoMapKeysOrValuesForRawIteration" do
    test "detects chunk_every" do
      [i] = check("Enum.chunk_every(Map.values(m), 2)")
      assert i.rule == :no_map_keys_or_values_for_raw_iteration
      assert i.message =~ "chunk_every"
      assert i.message =~ "Map.values"
    end

    test "detects chunk" do
      [i] = check("Enum.chunk(Map.values(m), 3)")
      assert i.message =~ "chunk"
    end

    test "detects chunk_by" do
      [i] = check("Enum.chunk_by(Map.values(m), fn v -> rem(v, 2) end)")
      assert i.message =~ "chunk_by"
    end

    test "detects chunk_while" do
      [i] =
        check(
          "Enum.chunk_while(Map.values(m), [], fn v, acc -> {:cont, [v | acc]} end, fn acc -> {:cont, acc} end)"
        )

      assert i.message =~ "chunk_while"
    end

    test "detects zip" do
      [i] = check("Enum.zip(Map.values(m))")
      assert i.message =~ "zip"
    end

    test "detects zip_with" do
      [i] = check("Enum.zip_with(Map.values(m), other, fn a, b -> a + b end)")
      assert i.message =~ "zip_with"
    end

    test "detects unzip" do
      [i] = check("Enum.unzip(Map.values(m))")
      assert i.message =~ "unzip"
    end

    test "detects split" do
      [i] = check("Enum.split(Map.values(m), 2)")
      assert i.message =~ "split"
    end

    test "detects split_while" do
      [i] = check("Enum.split_while(Map.values(m), fn v -> v > 0 end)")
      assert i.message =~ "split_while"
    end

    test "detects split_with" do
      [i] = check("Enum.split_with(Map.values(m), fn v -> v > 0 end)")
      assert i.message =~ "split_with"
    end

    test "detects with_index" do
      [i] = check("Enum.with_index(Map.values(m))")
      assert i.message =~ "with_index"
    end

    test "detects with_index/2" do
      [i] = check("Enum.with_index(Map.values(m), fn v, i -> {v, i + 1} end)")
      assert i.message =~ "with_index"
    end

    test "detects scan" do
      [i] = check("Enum.scan(Map.values(m), fn v, acc -> v + acc end)")
      assert i.message =~ "scan"
    end

    test "detects map_every" do
      [i] = check("Enum.map_every(Map.values(m), 2, fn v -> v * 2 end)")
      assert i.message =~ "map_every"
    end

    test "detects intersperse" do
      [i] = check("Enum.intersperse(Map.values(m), 0)")
      assert i.message =~ "intersperse"
    end

    test "detects tally" do
      [i] = check("Enum.tally(Map.values(m))")
      assert i.message =~ "tally"
    end

    test "detects member?" do
      [i] = check("Enum.member?(Map.values(m), 1)")
      assert i.message =~ "member?"
    end

    test "detects find_index" do
      [i] = check("Enum.find_index(Map.values(m), fn v -> v > 0 end)")
      assert i.message =~ "find_index"
    end

    test "detects fetch" do
      [i] = check("Enum.fetch(Map.values(m), 0)")
      assert i.message =~ "fetch"
    end

    test "detects fetch!" do
      [i] = check("Enum.fetch!(Map.values(m), 0)")
      assert i.message =~ "fetch!"
    end

    test "detects min_max" do
      [i] = check("Enum.min_max(Map.values(m))")
      assert i.message =~ "min_max"
    end

    test "detects min_max_by" do
      [i] = check("Enum.min_max_by(Map.values(m), fn v -> v end)")
      assert i.message =~ "min_max_by"
    end

    test "detects into" do
      [i] = check("Enum.into(Map.keys(m), %{a: 1})")
      assert i.message =~ "into"
    end

    test "detects into/3" do
      [i] = check("Enum.into(Map.values(m), %{}, fn v -> {v, true} end)")
      assert i.message =~ "into"
    end

    test "detects group_by/2 without value function" do
      [i] = check("Enum.group_by(Map.values(m), fn v -> rem(v, 2) end)")
      assert i.message =~ "group_by"
    end

    test "detects flat_map_reduce" do
      [i] = check("Enum.flat_map_reduce(Map.values(m), 0, fn v, acc -> {[v], acc + v} end)")
      assert i.message =~ "flat_map_reduce"
    end

    test "detects map_reduce" do
      [i] = check("Enum.map_reduce(Map.values(m), 0, fn v, acc -> {v * 2, acc + v} end)")
      assert i.message =~ "map_reduce"
    end

    test "detects reverse_slice" do
      [i] = check("Enum.reverse_slice(Map.values(m), 1, 3)")
      assert i.message =~ "reverse_slice"
    end

    test "pipe: Map.values |> Enum.with_index()" do
      [i] = check("Map.values(map) |> Enum.with_index()")
      assert i.message =~ "with_index"
    end

    test "pipe: Map.keys |> Enum.zip(other)" do
      [i] = check("Map.keys(m) |> Enum.zip(other)")
      assert i.message =~ "zip"
    end

    test "pipe: Map.values |> Enum.chunk_every(2)" do
      [i] = check("Map.values(m) |> Enum.chunk_every(2)")
      assert i.message =~ "chunk_every"
    end

    test "triple pipe: map |> Map.values() |> Enum.with_index()" do
      [i] = check("map |> Map.values() |> Enum.with_index()")
      assert i.message =~ "with_index"
    end

    test "triple pipe: map |> Map.keys() |> Enum.split(2)" do
      [i] = check("map |> Map.keys() |> Enum.split(2)")
      assert i.message =~ "split"
    end

    test "does not detect Map.values without Enum" do
      assert check("Map.values(m)") == []
    end

    test "does not detect Map.keys in non-Enum context" do
      assert check("length(Map.keys(m))") == []
    end

    test "does not detect group_by/3 (fixable)" do
      assert check("Enum.group_by(Map.values(m), fn v -> rem(v, 2) end, fn v -> v end)") == []
    end

    test "does not detect fixable callback functions" do
      assert check("Enum.all?(Map.values(m), fn v -> v == 0 end)") == []
      assert check("Enum.any?(Map.values(m), fn v -> v > 0 end)") == []
      assert check("Enum.map(Map.values(m), fn v -> v end)") == []
      assert check("Enum.flat_map(Map.values(m), fn v -> [v] end)") == []
      assert check("Enum.filter(Map.values(m), fn v -> v > 0 end)") == []
      assert check("Enum.reject(Map.values(m), fn v -> v > 0 end)") == []
      assert check("Enum.reduce(Map.values(m), 0, fn v, acc -> v + acc end)") == []
      assert check("Enum.each(Map.values(m), fn v -> IO.puts(v) end)") == []
      assert check("Enum.count(Map.values(m), fn v -> v > 0 end)") == []
      assert check("Enum.sort_by(Map.values(m), fn v -> v end)") == []
    end

    test "does not detect fixable no-callback functions" do
      assert check("Enum.max(Map.values(m))") == []
      assert check("Enum.min(Map.values(m))") == []
      assert check("Enum.sum(Map.values(m))") == []
      assert check("Enum.product(Map.values(m))") == []
      assert check("Enum.count(Map.values(m))") == []
      assert check("Enum.sort(Map.values(m))") == []
      assert check("Enum.random(Map.values(m))") == []
      assert check("Enum.join(Map.values(m))") == []
      assert check("Enum.empty?(Map.values(m))") == []
      assert check("Enum.reverse(Map.values(m))") == []
      assert check("Enum.take(Map.values(m), 3)") == []
      assert check("Enum.drop(Map.values(m), 2)") == []
      assert check("Enum.shuffle(Map.values(m))") == []
      assert check("Enum.sample(Map.values(m), 3)") == []
      assert check("Enum.uniq(Map.values(m))") == []
      assert check("Enum.dedup(Map.values(m))") == []
      assert check("Enum.frequencies(Map.values(m))") == []
      assert check("Enum.at(Map.values(m), 0)") == []
      assert check("Enum.find(Map.values(m), fn v -> v > 0 end)") == []
    end

    test "meta.line is set" do
      [i] = check("Enum.with_index(Map.values(m))")
      assert i.meta.line != nil
    end
  end
end
