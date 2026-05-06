defmodule Credence.Pattern.NoMapKeysOrValuesForIterationTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoMapKeysOrValuesForIteration.check(ast, [])
  end

  defp fix(code), do: Credence.Pattern.NoMapKeysOrValuesForIteration.fix(code, [])

  defp assert_fix(input, expected) do
    result = fix(input)

    assert normalize(result) == normalize(expected),
           "Fix mismatch.\nExpected:\n  #{expected}\nGot:\n  #{result}"
  end

  defp normalize(c), do: c |> Code.string_to_quoted!() |> Macro.to_string()

  # ═══════════════════════════════════════════════════════════════════
  # check
  # ═══════════════════════════════════════════════════════════════════

  describe "check" do
    test "passes iterating map directly" do
      assert check("""
             defmodule G do
               def f(m), do: Enum.all?(m, fn {_, v} -> v == 0 end)
             end
             """) == []
    end

    test "passes Map.values used without Enum" do
      assert check("Map.values(m)") == []
    end

    test "passes Map.keys in non-Enum context" do
      assert check("length(Map.keys(m))") == []
    end

    test "detects Enum.all?(Map.values(m), ...)" do
      [i] = check("Enum.all?(Map.values(degrees), fn v -> v == 0 end)")
      assert i.rule == :no_map_keys_or_values_for_iteration
      assert i.message =~ "Map.values"
      assert i.message =~ "Enum.all?"
    end

    test "detects Map.values(m) |> Enum.max()" do
      [i] = check("Map.values(map) |> Enum.max()")
      assert i.message =~ "Map.values"
      assert i.message =~ "Enum.max"
    end

    test "detects Map.keys(m) |> Enum.map(&to_string/1)" do
      [i] = check("Map.keys(map) |> Enum.map(&to_string/1)")
      assert i.message =~ "Map.keys"
      assert i.message =~ "Enum.map"
    end

    test "detects triple-pipe" do
      [i] = check("map |> Map.values() |> Enum.max()")
      assert i.message =~ "Map.values"
      assert i.message =~ "Enum.max"
    end

    test "detects Enum.sum(Map.values(m))" do
      [i] = check("Enum.sum(Map.values(m))")
      assert i.message =~ "sum"
    end

    test "detects Enum.filter(Map.values(m), ...)" do
      [i] = check("Enum.filter(Map.values(m), fn v -> v > 0 end)")
      assert i.message =~ "filter"
    end

    test "detects Enum.count(Map.values(m))" do
      [i] = check("Enum.count(Map.values(m))")
      assert i.message =~ "count"
    end

    test "meta.line is set" do
      [i] = check("Enum.all?(Map.values(m), fn v -> v == 0 end)")
      assert i.meta.line != nil
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — callback wrapping
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — callback wrapping" do
    test "Enum.all? with Map.values" do
      assert_fix(
        "Enum.all?(Map.values(degrees), fn v -> v == 0 end)",
        "Enum.all?(degrees, fn {_k, v} -> v == 0 end)"
      )
    end

    test "Enum.any? with Map.keys" do
      assert_fix(
        "Enum.any?(Map.keys(m), fn k -> k > 0 end)",
        "Enum.any?(m, fn {_k, k} -> k > 0 end)"
      )
    end

    test "Enum.each with Map.values" do
      result = fix("Enum.each(Map.values(m), fn v -> IO.puts(v) end)")
      assert result =~ "each"
      assert result =~ "IO.puts"
      refute result =~ "Map.values"
    end

    test "Enum.map with Map.values" do
      assert_fix(
        "Enum.map(Map.values(m), fn v -> v + 1 end)",
        "Enum.map(m, fn {_k, v} -> v + 1 end)"
      )
    end

    test "Enum.map with Map.keys" do
      assert_fix(
        "Enum.map(Map.keys(m), fn k -> to_string(k) end)",
        "Enum.map(m, fn {_k, k} -> to_string(k) end)"
      )
    end

    test "Enum.map with &func/1 capture on Map.keys" do
      result = fix("Map.keys(map) |> Enum.map(&to_string/1)")
      assert result =~ "Enum.map"
      assert result =~ "to_string"
      refute result =~ "Map.keys"
    end

    test "Enum.map with &func/1 capture on Map.values" do
      result = fix("Enum.map(Map.values(m), &to_string/1)")
      assert result =~ "Enum.map"
      assert result =~ "to_string"
      refute result =~ "Map.values"
    end

    test "Enum.flat_map" do
      assert_fix(
        "Enum.flat_map(Map.values(m), fn v -> [v] end)",
        "Enum.flat_map(m, fn {_k, v} -> [v] end)"
      )
    end

    test "Enum.count with predicate" do
      assert_fix(
        "Enum.count(Map.values(m), fn v -> v > 0 end)",
        "Enum.count(m, fn {_k, v} -> v > 0 end)"
      )
    end

    test "Enum.find_value" do
      result = fix("Enum.find_value(Map.values(m), fn v -> if v > 0, do: v end)")
      assert result =~ "find_value"
      refute result =~ "Map.values"
    end

    test "Enum.frequencies_by" do
      assert_fix(
        "Enum.frequencies_by(Map.values(m), fn v -> rem(v, 2) end)",
        "Enum.frequencies_by(m, fn {_k, v} -> rem(v, 2) end)"
      )
    end

    test "Enum.group_by/3 wraps both callbacks" do
      result =
        fix("Enum.group_by(Map.values(m), fn v -> rem(v, 2) end, fn v -> v * 2 end)")

      assert result =~ "group_by"
      refute result =~ "Map.values"
    end

    test "lambda with guard" do
      result = fix("Enum.all?(Map.values(m), fn v when is_integer(v) -> true end)")
      assert result =~ "is_integer(v)"
      refute result =~ "Map.values"
    end

    test "multi-clause lambda" do
      result =
        fix("""
        Enum.map(Map.values(m), fn
          0 -> :zero
          n -> n
        end)
        """)

      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "pipe: Map.keys |> Enum.map(fn k -> ...)" do
      assert_fix(
        "Map.keys(map) |> Enum.map(fn k -> to_string(k) end)",
        "map |> Enum.map(fn {_k, k} -> to_string(k) end)"
      )
    end

    test "triple pipe: map |> Map.values() |> Enum.map(...)" do
      assert_fix(
        "map |> Map.values() |> Enum.map(fn v -> v + 1 end)",
        "map |> Enum.map(fn {_k, v} -> v + 1 end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — reduce / reduce_while
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — reduce / reduce_while" do
    test "Enum.reduce with Map.values" do
      assert_fix(
        "Enum.reduce(Map.values(m), 0, fn v, acc -> v + acc end)",
        "Enum.reduce(m, 0, fn {_k, v}, acc -> v + acc end)"
      )
    end

    test "Enum.reduce with Map.keys" do
      assert_fix(
        "Enum.reduce(Map.keys(m), [], fn k, acc -> [to_string(k) | acc] end)",
        "Enum.reduce(m, [], fn {_k, k}, acc -> [to_string(k) | acc] end)"
      )
    end

    test "Enum.reduce_while" do
      result = fix("Enum.reduce_while(Map.values(m), 0, fn v, acc -> {:cont, acc + v} end)")
      assert result =~ "reduce_while"
      assert result =~ "acc"
      refute result =~ "Map.values"
    end

    test "pipe: Map.values |> Enum.reduce(acc, fn)" do
      assert_fix(
        "Map.values(m) |> Enum.reduce(0, fn v, acc -> v + acc end)",
        "m |> Enum.reduce(0, fn {_k, v}, acc -> v + acc end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — count / empty? (no callback)
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — count / empty?" do
    test "Enum.count(Map.values(m))" do
      assert_fix("Enum.count(Map.values(m))", "Enum.count(m)")
    end

    test "Enum.count(Map.keys(m))" do
      assert_fix("Enum.count(Map.keys(m))", "Enum.count(m)")
    end

    test "Map.values(m) |> Enum.count()" do
      assert_fix("Map.values(map) |> Enum.count()", "map |> Enum.count()")
    end

    test "map |> Map.keys() |> Enum.count()" do
      assert_fix("map |> Map.keys() |> Enum.count()", "map |> Enum.count()")
    end

    test "Enum.empty?(Map.values(m))" do
      assert_fix("Enum.empty?(Map.values(m))", "Enum.empty?(m)")
    end

    test "Enum.empty?(Map.keys(m))" do
      assert_fix("Enum.empty?(Map.keys(m))", "Enum.empty?(m)")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — max / min → max_by / min_by + elem
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — max / min" do
    test "Enum.max(Map.values(m))" do
      result = fix("Enum.max(Map.values(m))")
      assert result =~ "max_by"
      assert result =~ "elem"
      assert result =~ "v"
      refute result =~ "Map.values"
    end

    test "Enum.min(Map.keys(m))" do
      result = fix("Enum.min(Map.keys(m))")
      assert result =~ "min_by"
      assert result =~ "elem"
      assert result =~ "k"
      refute result =~ "Map.keys"
    end

    test "pipe: Map.values(m) |> Enum.max()" do
      result = fix("Map.values(map) |> Enum.max()")
      assert result =~ "max_by"
      assert result =~ "elem"
      refute result =~ "Map.values"
    end

    test "triple pipe: map |> Map.values() |> Enum.max()" do
      result = fix("map |> Map.values() |> Enum.max()")
      assert result =~ "max_by"
      assert result =~ "elem"
      refute result =~ "Map.values"
    end

    test "Enum.max_by(Map.values(m), fn ...)" do
      result = fix("Enum.max_by(Map.values(m), fn v -> v * 2 end)")
      assert result =~ "max_by"
      assert result =~ "elem"
      assert result =~ "v * 2"
      refute result =~ "Map.values"
    end

    test "Enum.min_by(Map.values(m), fn ...)" do
      result = fix("Enum.min_by(Map.values(m), fn v -> abs(v) end)")
      assert result =~ "min_by"
      assert result =~ "elem"
      assert result =~ "abs(v)"
      refute result =~ "Map.values"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — sum / product → reduce
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — sum / product" do
    test "Enum.sum(Map.values(m))" do
      result = fix("Enum.sum(Map.values(m))")
      assert result =~ "reduce"
      assert result =~ "0"
      assert result =~ "acc + v"
      refute result =~ "Map.values"
    end

    test "Enum.product(Map.keys(m))" do
      result = fix("Enum.product(Map.keys(m))")
      assert result =~ "reduce"
      assert result =~ "1"
      assert result =~ "acc * k"
      refute result =~ "Map.keys"
    end

    test "pipe: Map.values(m) |> Enum.sum()" do
      result = fix("Map.values(map) |> Enum.sum()")
      assert result =~ "reduce"
      assert result =~ "0"
      refute result =~ "Map.values"
    end

    test "triple pipe: map |> Map.values() |> Enum.sum()" do
      result = fix("map |> Map.values() |> Enum.sum()")
      assert result =~ "reduce"
      assert result =~ "0"
      refute result =~ "Map.values"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — find / at → case expression
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — find / at" do
    test "Enum.find(Map.values(m), fn v -> ...)" do
      result = fix("Enum.find(Map.values(m), fn v -> v > 0 end)")
      assert result =~ "case"
      assert result =~ "find"
      assert result =~ "nil"
      refute result =~ "Map.values"
    end

    test "Enum.find(Map.keys(m), fn k -> ...)" do
      result = fix("Enum.find(Map.keys(m), fn k -> k == :foo end)")
      assert result =~ "case"
      assert result =~ "find"
      refute result =~ "Map.keys"
    end

    test "Enum.find/3 with default" do
      result = fix("Enum.find(Map.values(m), :not_found, fn v -> v > 0 end)")
      assert result =~ "case"
      assert result =~ ":not_found"
      assert result =~ "find"
      refute result =~ "Map.values"
    end

    test "pipe: Map.keys(m) |> Enum.find(fn k -> ...)" do
      result = fix("Map.keys(m) |> Enum.find(fn k -> k > 0 end)")
      assert result =~ "case"
      assert result =~ "find"
      refute result =~ "Map.keys"
    end

    test "Enum.at(Map.values(m), 2)" do
      result = fix("Enum.at(Map.values(m), 2)")
      assert result =~ "case"
      assert result =~ "at"
      assert result =~ "nil"
      refute result =~ "Map.values"
    end

    test "Enum.at/3 with default" do
      result = fix("Enum.at(Map.values(m), 5, :out)")
      assert result =~ "case"
      assert result =~ ":out"
      assert result =~ "at"
      refute result =~ "Map.values"
    end

    test "Enum.at/3 with default false" do
      result = fix("Enum.at(Map.values(m), 5, false)")
      assert result =~ "case"
      assert result =~ "false"
      refute result =~ "Map.values"
    end

    test "pipe: Map.values(m) |> Enum.at(2)" do
      result = fix("Map.values(map) |> Enum.at(2)")
      assert result =~ "case"
      assert result =~ "at"
      assert result =~ "nil"
      refute result =~ "Map.values"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — random → elem
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — random" do
    test "Enum.random(Map.values(m))" do
      result = fix("Enum.random(Map.values(m))")
      assert result =~ "random"
      assert result =~ "elem"
      assert result =~ "1"
      refute result =~ "Map.values"
    end

    test "Enum.random(Map.keys(m))" do
      result = fix("Enum.random(Map.keys(m))")
      assert result =~ "random"
      assert result =~ "elem"
      assert result =~ "0"
      refute result =~ "Map.keys"
    end

    test "pipe: Map.keys(m) |> Enum.random()" do
      result = fix("Map.keys(map) |> Enum.random()")
      assert result =~ "random"
      assert result =~ "elem"
      assert result =~ "0"
      refute result =~ "Map.keys"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — join → map_join
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — join" do
    test "Enum.join(Map.values(m))" do
      result = fix("Enum.join(Map.values(m))")
      assert result =~ "map_join"
      assert result =~ "v"
      refute result =~ "Map.values"
    end

    test "Enum.join(Map.keys(m))" do
      result = fix("Enum.join(Map.keys(m))")
      assert result =~ "map_join"
      assert result =~ "k"
      refute result =~ "Map.keys"
    end

    test "Enum.join with separator" do
      result = fix(~s|Enum.join(Map.values(m), ",")|)
      assert result =~ "map_join"
      assert result =~ ~s|","|
      refute result =~ "Map.values"
    end

    test "pipe: Map.keys(m) |> Enum.join()" do
      result = fix("Map.keys(map) |> Enum.join()")
      assert result =~ "map_join"
      refute result =~ "Map.keys"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — filter / reject → chain with Enum.map
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — filter / reject" do
    test "Enum.filter with Map.values" do
      result = fix("Enum.filter(Map.values(m), fn v -> v > 0 end)")
      assert result =~ "filter"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "Enum.filter with Map.keys" do
      result = fix("Enum.filter(Map.keys(m), fn k -> k > 0 end)")
      assert result =~ "filter"
      assert result =~ "Enum.map"
      refute result =~ "Map.keys"
    end

    test "Enum.reject with Map.keys" do
      result = fix("Enum.reject(Map.keys(m), fn k -> k == :skip end)")
      assert result =~ "reject"
      assert result =~ "Enum.map"
      refute result =~ "Map.keys"
    end

    test "pipe: Map.values |> Enum.filter" do
      result = fix("Map.values(m) |> Enum.filter(fn v -> v > 0 end)")
      assert result =~ "filter"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "triple pipe: map |> Map.values() |> Enum.filter" do
      result = fix("m |> Map.values() |> Enum.filter(fn v -> v > 0 end)")
      assert result =~ "filter"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — sort → sort_by + map
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — sort" do
    test "Enum.sort(Map.values(m))" do
      result = fix("Enum.sort(Map.values(m))")
      assert result =~ "sort_by"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "Enum.sort(Map.values(m), :desc)" do
      result = fix("Enum.sort(Map.values(m), :desc)")
      assert result =~ "sort_by"
      assert result =~ ":desc"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "Enum.sort(Map.values(m), :asc)" do
      result = fix("Enum.sort(Map.values(m), :asc)")
      assert result =~ "sort_by"
      assert result =~ ":asc"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "Enum.sort with comparator lambda" do
      result = fix("Enum.sort(Map.values(m), fn a, b -> a <= b end)")
      assert result =~ "Enum.sort"
      assert result =~ "Enum.map"
      assert result =~ "a"
      assert result =~ "b"
      refute result =~ "Map.values"
    end

    test "Enum.sort_by with callback" do
      result = fix("Enum.sort_by(Map.values(m), fn v -> v end)")
      assert result =~ "sort_by"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "pipe: Map.values(m) |> Enum.sort()" do
      result = fix("Map.values(map) |> Enum.sort()")
      assert result =~ "sort_by"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "pipe: Map.values(m) |> Enum.sort(:desc)" do
      result = fix("Map.values(map) |> Enum.sort(:desc)")
      assert result =~ "sort_by"
      assert result =~ ":desc"
      refute result =~ "Map.values"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — uniq / dedup
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — uniq / dedup" do
    test "Enum.uniq(Map.values(m))" do
      result = fix("Enum.uniq(Map.values(m))")
      assert result =~ "uniq_by"
      assert result =~ "Enum.map"
      assert result =~ "v"
      refute result =~ "Map.values"
    end

    test "Enum.dedup(Map.keys(m))" do
      result = fix("Enum.dedup(Map.keys(m))")
      assert result =~ "dedup_by"
      assert result =~ "Enum.map"
      assert result =~ "k"
      refute result =~ "Map.keys"
    end

    test "Enum.uniq_by with callback" do
      result = fix("Enum.uniq_by(Map.values(m), fn v -> rem(v, 2) end)")
      assert result =~ "uniq_by"
      assert result =~ "Enum.map"
      assert result =~ "rem(v, 2)"
      refute result =~ "Map.values"
    end

    test "Enum.dedup_by with callback" do
      result = fix("Enum.dedup_by(Map.values(m), fn v -> rem(v, 2) end)")
      assert result =~ "dedup_by"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "pipe: Map.values(m) |> Enum.uniq()" do
      result = fix("Map.values(map) |> Enum.uniq()")
      assert result =~ "uniq_by"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — take / drop / take_while / drop_while
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — take / drop / take_while / drop_while" do
    test "Enum.take" do
      result = fix("Enum.take(Map.values(m), 3)")
      assert result =~ "take"
      assert result =~ "Enum.map"
      assert result =~ "3"
      refute result =~ "Map.values"
    end

    test "Enum.drop" do
      result = fix("Enum.drop(Map.keys(m), 2)")
      assert result =~ "drop"
      assert result =~ "Enum.map"
      assert result =~ "2"
      refute result =~ "Map.keys"
    end

    test "Enum.take_while" do
      result = fix("Enum.take_while(Map.values(m), fn v -> v > 0 end)")
      assert result =~ "take_while"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "Enum.drop_while" do
      result = fix("Enum.drop_while(Map.values(m), fn v -> v < 0 end)")
      assert result =~ "drop_while"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "pipe: Map.values(m) |> Enum.take(3)" do
      result = fix("Map.values(map) |> Enum.take(3)")
      assert result =~ "take"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — reverse / sample / shuffle / slice
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — reverse / sample / shuffle / slice" do
    test "Enum.reverse" do
      result = fix("Enum.reverse(Map.values(m))")
      assert result =~ "reverse"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "Enum.sample" do
      result = fix("Enum.sample(Map.values(m), 3)")
      assert result =~ "sample"
      assert result =~ "Enum.map"
      assert result =~ "3"
      refute result =~ "Map.values"
    end

    test "Enum.shuffle" do
      result = fix("Enum.shuffle(Map.keys(m))")
      assert result =~ "shuffle"
      assert result =~ "Enum.map"
      refute result =~ "Map.keys"
    end

    test "Enum.slice" do
      result = fix("Enum.slice(Map.values(m), 1..3)")
      assert result =~ "slice"
      assert result =~ "Enum.map"
      refute result =~ "Map.values"
    end

    test "Enum.slice with start + length" do
      result = fix("Enum.slice(Map.values(m), 1, 3)")
      assert result =~ "slice"
      assert result =~ "Enum.map"
      assert result =~ "1"
      assert result =~ "3"
      refute result =~ "Map.values"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — frequencies
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — frequencies" do
    test "Enum.frequencies(Map.values(m))" do
      result = fix("Enum.frequencies(Map.values(m))")
      assert result =~ "frequencies_by"
      assert result =~ "v"
      refute result =~ "Map.values"
    end

    test "Enum.frequencies(Map.keys(m))" do
      result = fix("Enum.frequencies(Map.keys(m))")
      assert result =~ "frequencies_by"
      assert result =~ "k"
      refute result =~ "Map.keys"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — module context / multiple patterns
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — module context" do
    test "fixes inside a module" do
      result =
        fix("""
        defmodule Example do
          def all_zero?(degrees) do
            Enum.all?(Map.values(degrees), fn v -> v == 0 end)
          end
        end
        """)

      assert result =~ "Enum.all?(degrees"
      refute result =~ "Map.values"
    end

    test "fixes multiple patterns in one file" do
      result =
        fix("""
        defmodule Example do
          def f(m), do: Enum.all?(Map.values(m), fn v -> v == 0 end)
          def g(m), do: Enum.count(Map.keys(m))
          def h(m), do: Enum.sum(Map.values(m))
        end
        """)

      assert result =~ "Enum.all?"
      assert result =~ "Enum.count"
      assert result =~ "reduce"
      refute result =~ "Map.values"
      refute result =~ "Map.keys"
    end

    test "fixes nested Enum calls independently" do
      result =
        fix("""
        defmodule Example do
          def f(m) do
            Enum.all?(Map.values(m), fn _v ->
              Enum.any?(Map.keys(m2), fn _k -> true end)
            end)
          end
        end
        """)

      refute result =~ "Map.values"
      refute result =~ "Map.keys"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix — variable/callback edge cases
  # ═══════════════════════════════════════════════════════════════════

  describe "fix — variable callback edge cases" do
    test "variable callback: Map.values is still removed" do
      # The match fires, wrap_fns passes the variable through unchanged,
      # so Map.values IS removed. This is correct — Enum.map(m, my_fn) is
      # still an improvement over Enum.map(Map.values(m), my_fn).
      result = fix("Enum.map(Map.values(m), my_mapper)")
      assert result =~ "Enum.map"
      assert result =~ "my_mapper"
      refute result =~ "Map.values"
    end

    test "complex capture: Map.values is still removed" do
      result = fix("Enum.map(Map.values(m), &(&1 + 1))")
      assert result =~ "Enum.map"
      assert result =~ "&(&1 + 1)"
      refute result =~ "Map.values"
    end

    test "Enum with not-in-fixable-list left unchanged" do
      code = "Enum.chunk_every(Map.values(m), 2)"
      assert fix(code) =~ "Map.values"
    end
  end
end
