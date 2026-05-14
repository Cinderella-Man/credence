defmodule Credence.Pattern.NoMapKeysOrValuesForIterationFixTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoMapKeysOrValuesForIteration.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoMapKeysOrValuesForIteration.fix(code, [])
  end

  # Normalize via AST round-trip to ignore whitespace/formatting differences
  defp assert_fix(input, expected) do
    result = fix(input)
    norm = &(&1 |> Code.string_to_quoted!() |> Macro.to_string())

    assert norm.(result) == norm.(expected),
           "Fix mismatch.\nInput:    #{input}\nExpected: #{expected}\nGot:      #{result}"
  end

  # ═══════════════════════════════════════════════════════════════
  # callback wrapping — nested
  # ═══════════════════════════════════════════════════════════════

  describe "callback wrapping — nested" do
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
      assert_fix(
        "Enum.each(Map.values(m), fn v -> IO.puts(v) end)",
        "Enum.each(m, fn {_k, v} -> IO.puts(v) end)"
      )
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
      assert_fix(
        "Enum.find_value(Map.values(m), fn v -> if v > 0, do: v end)",
        "Enum.find_value(m, fn {_k, v} -> if(v > 0, do: v) end)"
      )
    end

    test "Enum.frequencies_by" do
      assert_fix(
        "Enum.frequencies_by(Map.values(m), fn v -> rem(v, 2) end)",
        "Enum.frequencies_by(m, fn {_k, v} -> rem(v, 2) end)"
      )
    end

    test "Enum.group_by/3 wraps both callbacks" do
      assert_fix(
        "Enum.group_by(Map.values(m), fn v -> rem(v, 2) end, fn v -> v * 2 end)",
        "Enum.group_by(m, fn {_k, v} -> rem(v, 2) end, fn {_k, v} -> v * 2 end)"
      )
    end

    test "lambda with guard" do
      assert_fix(
        "Enum.all?(Map.values(m), fn v when is_integer(v) -> true end)",
        "Enum.all?(m, fn {_k, v} when is_integer(v) -> true end)"
      )
    end

    test "&func/1 capture on Map.values" do
      assert_fix(
        "Enum.map(Map.values(m), &to_string/1)",
        "Enum.map(m, fn {_k, x} -> to_string(x) end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # callback wrapping — pipe
  # ═══════════════════════════════════════════════════════════════

  describe "callback wrapping — pipe" do
    test "Map.keys |> Enum.map(fn)" do
      assert_fix(
        "Map.keys(map) |> Enum.map(fn k -> to_string(k) end)",
        "Enum.map(map, fn {_k, k} -> to_string(k) end)"
      )
    end

    test "Map.keys |> Enum.map(&func/1)" do
      assert_fix(
        "Map.keys(map) |> Enum.map(&to_string/1)",
        "Enum.map(map, fn {_k, x} -> to_string(x) end)"
      )
    end

    test "triple pipe: map |> Map.values() |> Enum.map" do
      assert_fix(
        "map |> Map.values() |> Enum.map(fn v -> v + 1 end)",
        "Enum.map(map, fn {_k, v} -> v + 1 end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # reduce / reduce_while
  # ═══════════════════════════════════════════════════════════════

  describe "reduce" do
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
      assert_fix(
        "Enum.reduce_while(Map.values(m), 0, fn v, acc -> {:cont, acc + v} end)",
        "Enum.reduce_while(m, 0, fn {_k, v}, acc -> {:cont, acc + v} end)"
      )
    end

    test "pipe: Map.values |> Enum.reduce" do
      assert_fix(
        "Map.values(m) |> Enum.reduce(0, fn v, acc -> v + acc end)",
        "Enum.reduce(m, 0, fn {_k, v}, acc -> v + acc end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # count / empty?
  # ═══════════════════════════════════════════════════════════════

  describe "count / empty?" do
    test "Enum.count(Map.values(m))" do
      assert_fix("Enum.count(Map.values(m))", "Enum.count(m)")
    end

    test "Enum.count(Map.keys(m))" do
      assert_fix("Enum.count(Map.keys(m))", "Enum.count(m)")
    end

    test "pipe: Map.values |> Enum.count()" do
      assert_fix("Map.values(map) |> Enum.count()", "Enum.count(map)")
    end

    test "triple pipe: map |> Map.keys() |> Enum.count()" do
      assert_fix("map |> Map.keys() |> Enum.count()", "Enum.count(map)")
    end

    test "Enum.empty?(Map.values(m))" do
      assert_fix("Enum.empty?(Map.values(m))", "Enum.empty?(m)")
    end

    test "Enum.empty?(Map.keys(m))" do
      assert_fix("Enum.empty?(Map.keys(m))", "Enum.empty?(m)")
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # max / min → max_by / min_by + elem
  # ═══════════════════════════════════════════════════════════════

  describe "max / min" do
    test "Enum.max(Map.values(m))" do
      assert_fix(
        "Enum.max(Map.values(m))",
        "elem(Enum.max_by(m, fn {_, v} -> v end), 1)"
      )
    end

    test "Enum.min(Map.keys(m))" do
      assert_fix(
        "Enum.min(Map.keys(m))",
        "elem(Enum.min_by(m, fn {k, _} -> k end), 0)"
      )
    end

    test "Enum.max_by with callback" do
      assert_fix(
        "Enum.max_by(Map.values(m), fn v -> v * 2 end)",
        "elem(Enum.max_by(m, fn {_k, v} -> v * 2 end), 1)"
      )
    end

    test "Enum.min_by with callback" do
      assert_fix(
        "Enum.min_by(Map.values(m), fn v -> abs(v) end)",
        "elem(Enum.min_by(m, fn {_k, v} -> abs(v) end), 1)"
      )
    end

    test "pipe: Map.values |> Enum.max()" do
      assert_fix(
        "Map.values(map) |> Enum.max()",
        "Enum.max_by(map, fn {_, v} -> v end) |> elem(1)"
      )
    end

    test "triple pipe: map |> Map.values() |> Enum.max()" do
      assert_fix(
        "map |> Map.values() |> Enum.max()",
        "Enum.max_by(map, fn {_, v} -> v end) |> elem(1)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # sum / product → reduce
  # ═══════════════════════════════════════════════════════════════

  describe "sum / product" do
    test "Enum.sum(Map.values(m))" do
      assert_fix(
        "Enum.sum(Map.values(m))",
        "Enum.reduce(m, 0, fn {_k, v}, acc -> acc + v end)"
      )
    end

    test "Enum.product(Map.keys(m))" do
      assert_fix(
        "Enum.product(Map.keys(m))",
        "Enum.reduce(m, 1, fn {k, _v}, acc -> acc * k end)"
      )
    end

    test "pipe: Map.values |> Enum.sum()" do
      assert_fix(
        "Map.values(map) |> Enum.sum()",
        "Enum.reduce(map, 0, fn {_k, v}, acc -> acc + v end)"
      )
    end

    test "triple pipe: map |> Map.values() |> Enum.sum()" do
      assert_fix(
        "map |> Map.values() |> Enum.sum()",
        "Enum.reduce(map, 0, fn {_k, v}, acc -> acc + v end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # find / at → case expression
  # ═══════════════════════════════════════════════════════════════

  describe "find / at" do
    test "Enum.find(Map.values(m), fn ...)" do
      assert_fix(
        "Enum.find(Map.values(m), fn v -> v > 0 end)",
        "case Enum.find(m, fn {_k, v} -> v > 0 end) do nil -> nil; {_k, v} -> v end"
      )
    end

    test "Enum.find(Map.keys(m), fn ...)" do
      assert_fix(
        "Enum.find(Map.keys(m), fn k -> k == :foo end)",
        "case Enum.find(m, fn {_k, k} -> k == :foo end) do nil -> nil; {k, _v} -> k end"
      )
    end

    test "Enum.find/3 with default" do
      assert_fix(
        "Enum.find(Map.values(m), :not_found, fn v -> v > 0 end)",
        "case Enum.find(m, fn {_k, v} -> v > 0 end) do nil -> :not_found; {_k, v} -> v end"
      )
    end

    test "Enum.at(Map.values(m), 2)" do
      assert_fix(
        "Enum.at(Map.values(m), 2)",
        "case Enum.at(m, 2) do nil -> nil; {_k, v} -> v end"
      )
    end

    test "Enum.at/3 with default" do
      assert_fix(
        "Enum.at(Map.values(m), 5, :out)",
        "case Enum.at(m, 5) do nil -> :out; {_k, v} -> v end"
      )
    end

    test "Enum.at/3 with default false" do
      assert_fix(
        "Enum.at(Map.values(m), 5, false)",
        "case Enum.at(m, 5) do nil -> false; {_k, v} -> v end"
      )
    end

    test "pipe: Map.keys |> Enum.find" do
      assert_fix(
        "Map.keys(m) |> Enum.find(fn k -> k > 0 end)",
        "case Enum.find(m, fn {_k, k} -> k > 0 end) do nil -> nil; {k, _v} -> k end"
      )
    end

    test "pipe: Map.values |> Enum.at(2)" do
      assert_fix(
        "Map.values(map) |> Enum.at(2)",
        "case Enum.at(map, 2) do nil -> nil; {_k, v} -> v end"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # random → elem
  # ═══════════════════════════════════════════════════════════════

  describe "random" do
    test "Enum.random(Map.values(m))" do
      assert_fix("Enum.random(Map.values(m))", "elem(Enum.random(m), 1)")
    end

    test "Enum.random(Map.keys(m))" do
      assert_fix("Enum.random(Map.keys(m))", "elem(Enum.random(m), 0)")
    end

    test "pipe: Map.keys |> Enum.random()" do
      assert_fix(
        "Map.keys(map) |> Enum.random()",
        "Enum.random(map) |> elem(0)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # join → map_join (pipe collapses to nested call)
  # ═══════════════════════════════════════════════════════════════

  describe "join" do
    test "Enum.join(Map.values(m))" do
      assert_fix(
        "Enum.join(Map.values(m))",
        "Enum.map_join(m, \"\", fn {_, v} -> v end)"
      )
    end

    test "Enum.join(Map.keys(m))" do
      assert_fix(
        "Enum.join(Map.keys(m))",
        "Enum.map_join(m, \"\", fn {k, _} -> k end)"
      )
    end

    test "Enum.join with separator" do
      assert_fix(
        "Enum.join(Map.values(m), \",\")",
        "Enum.map_join(m, \",\", fn {_, v} -> v end)"
      )
    end

    test "pipe collapses to nested call" do
      assert_fix(
        "Map.keys(map) |> Enum.join()",
        "Enum.map_join(map, \"\", fn {k, _} -> k end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # filter / reject → filter + Enum.map extractor
  #
  # REGRESSION: ex() must produce fn {_, v} -> v end (1-arity)
  #             not fn _, v -> v end (2-arity, crashes at runtime)
  # ═══════════════════════════════════════════════════════════════

  describe "filter / reject (exercises ex() extractor fix)" do
    test "Enum.filter(Map.values(m), fn ...)" do
      assert_fix(
        "Enum.filter(Map.values(m), fn v -> v > 0 end)",
        "Enum.map(Enum.filter(m, fn {_k, v} -> v > 0 end), fn {_, v} -> v end)"
      )
    end

    test "Enum.filter(Map.keys(m), fn ...)" do
      assert_fix(
        "Enum.filter(Map.keys(m), fn k -> k > 0 end)",
        "Enum.map(Enum.filter(m, fn {_k, k} -> k > 0 end), fn {k, _} -> k end)"
      )
    end

    test "Enum.reject(Map.keys(m), fn ...)" do
      assert_fix(
        "Enum.reject(Map.keys(m), fn k -> k == :skip end)",
        "Enum.map(Enum.reject(m, fn {_k, k} -> k == :skip end), fn {k, _} -> k end)"
      )
    end

    test "pipe: Map.values |> Enum.filter" do
      assert_fix(
        "Map.values(m) |> Enum.filter(fn v -> v > 0 end)",
        "Enum.map(Enum.filter(m, fn {_k, v} -> v > 0 end), fn {_, v} -> v end)"
      )
    end

    test "triple pipe: m |> Map.values() |> Enum.filter" do
      assert_fix(
        "m |> Map.values() |> Enum.filter(fn v -> v > 0 end)",
        "Enum.map(Enum.filter(m, fn {_k, v} -> v > 0 end), fn {_, v} -> v end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # sort (exercises both ex() fix and sort double-wrap fix)
  # ═══════════════════════════════════════════════════════════════

  describe "sort" do
    test "Enum.sort(Map.values(m))" do
      assert_fix(
        "Enum.sort(Map.values(m))",
        "Enum.map(Enum.sort_by(m, fn {_, v} -> v end), fn {_, v} -> v end)"
      )
    end

    test "Enum.sort with :desc" do
      assert_fix(
        "Enum.sort(Map.values(m), :desc)",
        "Enum.map(Enum.sort_by(m, fn {_, v} -> v end, :desc), fn {_, v} -> v end)"
      )
    end

    test "Enum.sort with :asc" do
      assert_fix(
        "Enum.sort(Map.values(m), :asc)",
        "Enum.map(Enum.sort_by(m, fn {_, v} -> v end, :asc), fn {_, v} -> v end)"
      )
    end

    test "Enum.sort with comparator lambda" do
      assert_fix(
        "Enum.sort(Map.values(m), fn a, b -> a <= b end)",
        "Enum.map(Enum.sort(m, fn {_k, a}, {_k, b} -> a <= b end), fn {_, v} -> v end)"
      )
    end

    test "Enum.sort_by with callback" do
      assert_fix(
        "Enum.sort_by(Map.values(m), fn v -> v end)",
        "Enum.map(Enum.sort_by(m, fn {_k, v} -> v end), fn {_, v} -> v end)"
      )
    end

    test "pipe: Map.values |> Enum.sort()" do
      assert_fix(
        "Map.values(map) |> Enum.sort()",
        "Enum.map(Enum.sort_by(map, fn {_, v} -> v end), fn {_, v} -> v end)"
      )
    end

    test "pipe: Map.values |> Enum.sort(:desc)" do
      assert_fix(
        "Map.values(map) |> Enum.sort(:desc)",
        "Enum.map(Enum.sort_by(map, fn {_, v} -> v end, :desc), fn {_, v} -> v end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # uniq / dedup
  # ═══════════════════════════════════════════════════════════════

  describe "uniq / dedup" do
    test "Enum.uniq(Map.values(m))" do
      assert_fix(
        "Enum.uniq(Map.values(m))",
        "Enum.map(Enum.uniq_by(m, fn {_, v} -> v end), fn {_, v} -> v end)"
      )
    end

    test "Enum.dedup(Map.keys(m))" do
      assert_fix(
        "Enum.dedup(Map.keys(m))",
        "Enum.map(Enum.dedup_by(m, fn {k, _} -> k end), fn {k, _} -> k end)"
      )
    end

    test "Enum.uniq_by with callback" do
      assert_fix(
        "Enum.uniq_by(Map.values(m), fn v -> rem(v, 2) end)",
        "Enum.map(Enum.uniq_by(m, fn {_k, v} -> rem(v, 2) end), fn {_, v} -> v end)"
      )
    end

    test "Enum.dedup_by with callback" do
      assert_fix(
        "Enum.dedup_by(Map.values(m), fn v -> rem(v, 2) end)",
        "Enum.map(Enum.dedup_by(m, fn {_k, v} -> rem(v, 2) end), fn {_, v} -> v end)"
      )
    end

    test "pipe: Map.values |> Enum.uniq()" do
      assert_fix(
        "Map.values(map) |> Enum.uniq()",
        "Enum.map(Enum.uniq_by(map, fn {_, v} -> v end), fn {_, v} -> v end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # take / drop / take_while / drop_while
  # ═══════════════════════════════════════════════════════════════

  describe "take / drop / take_while / drop_while" do
    test "Enum.take(Map.values(m), 3)" do
      assert_fix(
        "Enum.take(Map.values(m), 3)",
        "Enum.map(Enum.take(m, 3), fn {_, v} -> v end)"
      )
    end

    test "Enum.drop(Map.keys(m), 2)" do
      assert_fix(
        "Enum.drop(Map.keys(m), 2)",
        "Enum.map(Enum.drop(m, 2), fn {k, _} -> k end)"
      )
    end

    test "Enum.take_while with callback" do
      assert_fix(
        "Enum.take_while(Map.values(m), fn v -> v > 0 end)",
        "Enum.map(Enum.take_while(m, fn {_k, v} -> v > 0 end), fn {_, v} -> v end)"
      )
    end

    test "Enum.drop_while with callback" do
      assert_fix(
        "Enum.drop_while(Map.values(m), fn v -> v < 0 end)",
        "Enum.map(Enum.drop_while(m, fn {_k, v} -> v < 0 end), fn {_, v} -> v end)"
      )
    end

    test "pipe: Map.values |> Enum.take(3)" do
      assert_fix(
        "Map.values(map) |> Enum.take(3)",
        "Enum.map(Enum.take(map, 3), fn {_, v} -> v end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # reverse / sample / shuffle / slice
  # ═══════════════════════════════════════════════════════════════

  describe "reverse / sample / shuffle / slice" do
    test "Enum.reverse(Map.values(m))" do
      assert_fix(
        "Enum.reverse(Map.values(m))",
        "Enum.map(Enum.reverse(m), fn {_, v} -> v end)"
      )
    end

    test "Enum.sample(Map.values(m), 3)" do
      assert_fix(
        "Enum.sample(Map.values(m), 3)",
        "Enum.map(Enum.sample(m, 3), fn {_, v} -> v end)"
      )
    end

    test "Enum.shuffle(Map.keys(m))" do
      assert_fix(
        "Enum.shuffle(Map.keys(m))",
        "Enum.map(Enum.shuffle(m), fn {k, _} -> k end)"
      )
    end

    test "Enum.slice with range" do
      assert_fix(
        "Enum.slice(Map.values(m), 1..3)",
        "Enum.map(Enum.slice(m, 1..3), fn {_, v} -> v end)"
      )
    end

    test "Enum.slice with start + length" do
      assert_fix(
        "Enum.slice(Map.values(m), 1, 3)",
        "Enum.map(Enum.slice(m, 1, 3), fn {_, v} -> v end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # frequencies
  # ═══════════════════════════════════════════════════════════════

  describe "frequencies" do
    test "Enum.frequencies(Map.values(m))" do
      assert_fix(
        "Enum.frequencies(Map.values(m))",
        "Enum.frequencies_by(m, fn {_, v} -> v end)"
      )
    end

    test "Enum.frequencies(Map.keys(m))" do
      assert_fix(
        "Enum.frequencies(Map.keys(m))",
        "Enum.frequencies_by(m, fn {k, _} -> k end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # no-ops
  # ═══════════════════════════════════════════════════════════════

  describe "no-ops" do
    test "unfixable func left unchanged" do
      code = "Enum.chunk_every(Map.values(m), 2)"
      assert fix(code) =~ "Map.values"
    end

    test "variable callback still removes Map.values" do
      assert_fix(
        "Enum.map(Map.values(m), my_mapper)",
        "Enum.map(m, my_mapper)"
      )
    end

    test "complex capture &(&1 + 1) is converted and wrapped" do
      assert_fix(
        "Enum.map(Map.values(m), &(&1 + 1))",
        "Enum.map(m, fn {_k, x} -> x + 1 end)"
      )
    end

    test "complex piped capture &(&1 + 1) is converted and wrapped" do
      assert_fix(
        "m |> Map.values() |> Enum.map(&(&1 + 1))",
        "Enum.map(m, fn {_k, x} -> x + 1 end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # module context
  # ═══════════════════════════════════════════════════════════════

  describe "module context" do
    test "fixes inside a module" do
      assert_fix(
        """
        defmodule Example do
          def all_zero?(degrees) do
            Enum.all?(Map.values(degrees), fn v -> v == 0 end)
          end
        end
        """,
        """
        defmodule Example do
          def all_zero?(degrees) do
            Enum.all?(degrees, fn {_k, v} -> v == 0 end)
          end
        end
        """
      )
    end

    test "fixes multiple patterns in one file" do
      assert_fix(
        """
        defmodule Example do
          def f(m), do: Enum.all?(Map.values(m), fn v -> v == 0 end)
          def g(m), do: Enum.count(Map.keys(m))
          def h(m), do: Enum.sum(Map.values(m))
        end
        """,
        """
        defmodule Example do
          def f(m), do: Enum.all?(m, fn {_k, v} -> v == 0 end)
          def g(m), do: Enum.count(m)
          def h(m), do: Enum.reduce(m, 0, fn {_k, v}, acc -> acc + v end)
        end
        """
      )
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

  # ═══════════════════════════════════════════════════════════════
  # round-trip: fixed code has zero issues and is valid Elixir
  # ═══════════════════════════════════════════════════════════════

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(m), do: Enum.all?(Map.values(m), fn v -> v == 0 end)
        def b(m), do: Enum.count(Map.values(m))
        def c(m), do: Enum.sum(Map.values(m))
        def d(m), do: Enum.filter(Map.values(m), fn v -> v > 0 end)
        def e(m), do: Map.values(m) |> Enum.max()
        def f(m), do: Enum.join(Map.values(m))
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(m), do: Enum.all?(Map.values(m), fn v -> v == 0 end)
        def b(m), do: Enum.filter(Map.values(m), fn v -> v > 0 end)
        def c(m), do: Enum.sort(Map.values(m))
        def d(m), do: Map.keys(m) |> Enum.join()
      end
      """

      assert {:ok, _} = Code.string_to_quoted(fix(code))
    end

    test "preserves heredoc when no rewrite applies" do
      code = ~S'''
      defmodule M do
        @moduledoc """
        line 1
        line 2
        """
        def noop(x), do: x
      end
      '''

      assert fix(code) == code
    end
  end
end
