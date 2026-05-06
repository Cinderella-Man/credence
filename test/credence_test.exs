defmodule CredenceTest do
  @moduledoc """
  Sanity tests: idiomatic Elixir solutions that should pass ALL Credence rules.

  When a new rule is added, run these tests to make sure it doesn't produce
  false positives on clean, idiomatic code. If any of these fail, the new
  rule is too broad and needs tightening.
  """
  use ExUnit.Case

  defp assert_clean(code) do
    result = Credence.analyze(code)

    if result.valid do
      assert true
    else
      rules_triggered = Enum.map(result.issues, & &1.rule) |> Enum.uniq()

      flunk(
        "Expected no issues but got #{length(result.issues)}: #{inspect(rules_triggered)}\n" <>
          Enum.map_join(result.issues, "\n", fn i ->
            "  [#{i.rule}: #{i.message} (line #{i.meta[:line]})"
          end)
      )
    end
  end

  describe "analyze works" do
    test "prepend + reverse pattern in reduce" do
      assert_clean("""
      defmodule DoubleList do
        def double(list) do
          list
          |> Enum.reduce([], fn item, acc -> [item * 2 | acc] end)
          |> Enum.reverse()
        end
      end
      """)
    end

    test "Enum.map, filter, and pipe chains" do
      assert_clean("""
      defmodule DataPipeline do
        def process(records) do
          records
          |> Enum.filter(&(&1.active))
          |> Enum.map(& &1.name)
          |> Enum.sort()
          |> Enum.uniq()
        end
      end
      """)
    end

    test "pattern matching in function heads for dispatch" do
      assert_clean("""
      defmodule Factorial do
        def factorial(0), do: 1
        def factorial(num) when is_integer(num) and num > 0, do: do_factorial(num, 1)

        defp do_factorial(1, acc), do: acc
        defp do_factorial(num, acc), do: do_factorial(num - 1, num * acc)
      end
      """)
    end

    test "multi-clause recursive functions with pattern matching" do
      assert_clean("""
      defmodule ListSum do
        def sum([]), do: 0
        def sum([head | tail]), do: head + sum(tail)
      end
      """)
    end

    test "Enum.sort with :desc for descending order" do
      assert_clean("""
      defmodule Sorter do
        def descending(nums) do
          Enum.sort(nums, :desc)
        end
      end
      """)
    end
  end

  describe "idiomatic string processing" do
    test "String.reverse for palindrome check" do
      assert_clean("""
      defmodule Palindrome do
        def palindrome?(text) do
          cleaned =
            text
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9]/, "")

          cleaned == String.reverse(cleaned)
        end
      end
      """)
    end

    test "String.graphemes with Enum.frequencies" do
      assert_clean("""
      defmodule CharFrequency do
        def char_frequency(string) do
          string |> String.graphemes() |> Enum.frequencies()
        end
      end
      """)
    end

    test "binary pattern matching for ASCII parsing" do
      assert_clean("""
      defmodule BracketChecker do
        def balanced?(input) when is_binary(input), do: check(input, [])

        defp check(<<>>, stack), do: stack == []
        defp check(<<"(", rest::binary>>, stack), do: check(rest, [?( | stack])
        defp check(<<")", rest::binary>>, [?( | tail]), do: check(rest, tail)
        defp check(<<")", _rest::binary>>, _stack), do: false
        defp check(<<_::utf8, rest::binary>>, stack), do: check(rest, stack)
      end
      """)
    end

    test "Enum.join without redundant empty separator" do
      assert_clean("""
      defmodule Joiner do
        def join_words(words) do
          Enum.join(words)
        end

        def join_with_comma(list) do
          Enum.join(list, ", ")
        end
      end
      """)
    end

    test "iodata accumulation for string building" do
      assert_clean("""
      defmodule StringBuilder do
        def build(graphemes) do
          graphemes
          |> Enum.reduce([], fn char, acc -> [char | acc] end)
          |> Enum.reverse()
          |> IO.iodata_to_binary()
        end
      end
      """)
    end
  end

  describe "idiomatic map usage" do
    test "Enum.frequencies instead of manual counting" do
      assert_clean("""
      defmodule WordCount do
        def count(words) do
          Enum.frequencies(words)
        end
      end
      """)
    end

    test "Map.get + Map.put instead of Map.update + Map.fetch" do
      assert_clean("""
      defmodule Counter do
        def increment(map, key) do
          count = Map.get(map, key, 0) + 1
          Map.put(map, key, count)
        end
      end
      """)
    end

    test "iterating map directly without Map.values or Map.keys" do
      assert_clean("""
      defmodule MapChecker do
        def all_positive?(data) do
          Enum.all?(data, fn {_key, value} -> value > 0 end)
        end

        def key_strings(entries) do
          Enum.map(entries, fn {key, _value} -> to_string(key) end)
        end
      end
      """)
    end

    test "MapSet for efficient membership checks in reduce" do
      assert_clean("""
      defmodule AllowlistFilter do
        def filter_allowed(items, allowed_list) do
          allowed = MapSet.new(allowed_list)

          Enum.filter(items, fn item ->
            MapSet.member?(allowed, item)
          end)
        end
      end
      """)
    end

    test "group-by pattern with Map.update and list default" do
      assert_clean("""
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
      """)
    end
  end

  describe "idiomatic numeric and algorithmic patterns" do
    test "Gauss formula for missing number" do
      assert_clean("""
      defmodule MissingNumber do
        def missing_number(nums) do
          n = length(nums)
          div(n * (n + 1), 2) - Enum.sum(nums)
        end
      end
      """)
    end

    test "Kadane's algorithm with reduce" do
      assert_clean("""
      defmodule MaxSubarray do
        def max_subarray_sum([head | tail]) do
          {_current, global} =
            Enum.reduce(tail, {head, head}, fn num, {curr, glob} ->
              new_curr = max(num, curr + num)
              {new_curr, max(glob, new_curr)}
            end)

          global
        end
      end
      """)
    end

    test "sliding window with Enum.zip" do
      assert_clean("""
      defmodule MaxAverage do
        def find_max_average(nums, window_size) do
          {window, rest} = Enum.split(nums, window_size)
          initial_sum = Enum.sum(window)

          Stream.zip(rest, nums)
          |> Enum.reduce({initial_sum, initial_sum / window_size}, fn {incoming, outgoing}, {sum, max_avg} ->
            new_sum = sum + incoming - outgoing
            {new_sum, max(max_avg, new_sum / window_size)}
          end)
          |> elem(1)
        end
      end
      """)
    end

    test "stock profit with single-pass reduce" do
      assert_clean("""
      defmodule StockProfit do
        def max_profit([]), do: 0

        def max_profit([first | rest]) do
          {_, profit} =
            Enum.reduce(rest, {first, 0}, fn price, {min_p, max_p} ->
              {min(min_p, price), max(max_p, price - min_p)}
            end)

          profit
        end
      end
      """)
    end

    test "tail-recursive Fibonacci with accumulator" do
      assert_clean("""
      defmodule Fibonacci do
        def fib(0), do: 0
        def fib(1), do: 1

        def fib(num) when is_integer(num) and num > 1 do
          fib_loop(num, 0, 1)
        end

        defp fib_loop(1, _prev, curr), do: curr
        defp fib_loop(num, prev, curr), do: fib_loop(num - 1, curr, prev + curr)
      end
      """)
    end

    test "Integer.digits for digit extraction" do
      assert_clean("""
      defmodule DigitSum do
        def sum_of_digits(number) do
          number |> abs() |> Integer.digits() |> Enum.sum()
        end
      end
      """)
    end
  end

  describe "idiomatic control flow" do
    test "predicate with ? suffix" do
      assert_clean("""
      defmodule Validator do
        def valid?(age) when is_integer(age) and age > 0, do: true
        def valid?(_), do: false
      end
      """)
    end

    test "pattern matching on literals in function heads (not when ==)" do
      assert_clean("""
      defmodule Staircase do
        def count_ways(0), do: 1
        def count_ways(1), do: 1
        def count_ways(2), do: 2
        def count_ways(steps) when steps > 2, do: do_count(steps - 2, 1, 1, 2)

        defp do_count(0, _, _, prev1), do: prev1
        defp do_count(remaining, prev3, prev2, prev1), do: do_count(remaining - 1, prev2, prev1, prev3 + prev2 + prev1)
      end
      """)
    end

    test "with block for chaining results" do
      assert_clean("""
      defmodule Parser do
        def parse(input) do
          with {:ok, tokens} <- tokenize(input),
               {:ok, ast} <- build_ast(tokens) do
            {:ok, ast}
          end
        end

        defp tokenize(input), do: {:ok, String.split(input)}
        defp build_ast(tokens), do: {:ok, tokens}
      end
      """)
    end

    test "word grouping by length" do
      assert_clean("""
      defmodule WordGrouper do
        def group_by_length(text) when is_binary(text) do
          text
          |> String.split(~r/\W+/u, trim: true)
          |> Enum.group_by(&String.length/1)
        end
      end
      """)
    end

    test "recursive word counting" do
      assert_clean("""
      defmodule RecursiveCounter do
        def count(text) when is_binary(text) do
          text
          |> String.downcase()
          |> String.split(~r/\W+/u, trim: true)
          |> do_count(%{})
        end

        defp do_count([], acc), do: acc

        defp do_count([word | rest], acc) do
          updated =
            Map.update(acc, word, 1, fn count -> count + 1 end)

          do_count(rest, updated)
        end
      end
      """)
    end

    test "chart counting" do
      assert_clean("""
      defmodule CharCounter do
        def count(text) when is_binary(text) do
          text
          |> String.graphemes()
          |> Enum.frequencies()
        end
      end
      """)
    end

    test "unique word extraction" do
      assert_clean("""
      defmodule UniqueWords do
        def extract(text) when is_binary(text) do
          text
          |> String.downcase()
          |> String.split(~r/\W+/u, trim: true)
          |> MapSet.new()
        end
      end
      """)
    end

    test "longest word extraction" do
      assert_clean("""
      defmodule LongestWord do
        def find(text) when is_binary(text) do
          text
          |> String.split(~r/\W+/u, trim: true)
          |> Enum.max_by(&String.length/1, fn -> "" end)
        end
      end
      """)
    end

    test "index by first letter" do
      assert_clean("""
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
      """)
    end

    test "then/2 in pipelines" do
      assert_clean("""
      defmodule PipeHelper do
        def process(list) do
          list
          |> Enum.sort()
          |> then(fn sorted -> [0 | sorted] end)
        end
      end
      """)
    end
  end

  describe "idiomatic data structures" do
    test "MapSet.intersection for set operations" do
      assert_clean("""
      defmodule SetOps do
        def intersection(list1, list2) do
          MapSet.intersection(MapSet.new(list1), MapSet.new(list2))
          |> MapSet.to_list()
        end
      end
      """)
    end

    test "Stream.with_index for lazy indexing" do
      assert_clean("""
      defmodule IndexedProcessor do
        def process(list) do
          list
          |> Stream.with_index()
          |> Enum.reduce([], fn {val, idx}, acc ->
            [{idx, val * 2} | acc]
          end)
          |> Enum.reverse()
        end
      end
      """)
    end

    test "Enum.sort_by for sorting with key function" do
      assert_clean("""
      defmodule Sorter do
        def by_length(strings) do
          Enum.sort_by(strings, &String.length/1)
        end

        def by_name_desc(records) do
          Enum.sort_by(records, & &1.name, :desc)
        end
      end
      """)
    end

    test "reduce with distinct new_ prefixed accumulator variables" do
      assert_clean("""
      defmodule Processor do
        def process(items) do
          Enum.reduce(items, {0, []}, fn item, {count, acc} ->
            new_count = count + 1
            new_acc = [item * 2 | acc]
            {new_count, new_acc}
          end)
        end
      end
      """)
    end
  end

  describe "edge cases that should NOT trigger rules" do
    test "list ++ outside of any loop" do
      assert_clean("""
      defmodule SafeConcat do
        def concat(left, right), do: left ++ right
        def prepend_header(list), do: ["header"] ++ list
      end
      """)
    end

    test "String.length compared to non-1 values" do
      assert_clean("""
      defmodule LengthCheck do
        def long_enough?(name), do: String.length(name) >= 8
        def too_short?(name), do: String.length(name) < 3
      end
      """)
    end

    test "Enum.at outside of any loop (single access)" do
      assert_clean("""
      defmodule SingleAccess do
        def middle(list) do
          mid = div(length(list), 2)
          Enum.at(list, mid)
        end
      end
      """)
    end

    test "Enum.drop and Enum.take with positive counts" do
      assert_clean("""
      defmodule SliceOps do
        def skip_first_three(list), do: Enum.drop(list, 3)
        def take_five(list), do: Enum.take(list, 5)
      end
      """)
    end

    test "Map.put with non-boolean meaningful values" do
      assert_clean("""
      defmodule Config do
        def set_defaults(map) do
          map
          |> Map.put(:timeout, 5000)
          |> Map.put(:retries, 3)
          |> Map.put(:name, "default")
        end
      end
      """)
    end

    test "Map.update with non-frequency default (group-by)" do
      assert_clean("""
      defmodule Grouper do
        def group_by_type(items) do
          Enum.reduce(items, %{}, fn item, acc ->
            Map.update(acc, item.type, [item], fn existing ->
              [item | existing]
            end)
          end)
        end
      end
      """)
    end

    test "length/1 in function body (not guard)" do
      assert_clean("""
      defmodule BodyLength do
        def process(list) when is_list(list) do
          n = length(list)
          div(n * (n + 1), 2)
        end
      end
      """)
    end

    test "anonymous function without rebinding params" do
      assert_clean("""
      defmodule CleanReduce do
        def sum_evens(list) do
          Enum.reduce(list, 0, fn num, acc ->
            if rem(num, 2) == 0, do: acc + num, else: acc
          end)
        end
      end
      """)
    end

    test "Enum.reduce_while — early termination in a fold" do
      assert_clean("""
      defmodule BudgetPacker do
        def pack(items, budget) do
          Enum.reduce_while(items, {budget, []}, fn {name, cost}, {remaining, picked} ->
            if cost <= remaining do
              {:cont, {remaining - cost, [name | picked]}}
            else
              {:halt, {remaining, picked}}
            end
          end)
          |> elem(1)
          |> Enum.reverse()
        end
      end
      """)
    end

    test "Enum.flat_map — map then flatten in one pass" do
      assert_clean("""
      defmodule Expander do
        def expand_ranges(ranges) do
          Enum.flat_map(ranges, fn {lo, hi} -> Enum.to_list(lo..hi) end)
        end
      end
      """)
    end

    test "Enum.chunk_every — partition a list into fixed-size windows" do
      assert_clean("""
      defmodule Batcher do
        def batch(items, size), do: Enum.chunk_every(items, size)

        def ngrams(words, window_size), do: Enum.chunk_every(words, window_size, 1, :discard)
      end
      """)
    end

    test "Enum.chunk_by — split when a key function changes" do
      assert_clean("""
      defmodule RunLength do
      def encode(list) do
      list
      |> Enum.chunk_by(& &1)
      |> Enum.map(fn chunk -> {hd(chunk), length(chunk)} end)
      end
      end
      """)
    end

    test "Enum.zip_with — zip and transform in one step" do
      assert_clean("""
      defmodule VectorMath do
        def dot(left, right), do: Enum.zip_with(left, right, &Kernel.*/2) |> Enum.sum()
        def add(left, right), do: Enum.zip_with(left, right, &Kernel.+/2)
      end
      """)
    end

    test "Enum.map_reduce — produce a mapped list and an accumulator simultaneously" do
      assert_clean("""
      defmodule RunningTotal do
        def with_running_sum(nums) do
          {tagged, _total} =
            Enum.map_reduce(nums, 0, fn num, acc ->
              new_acc = acc + num
              {{num, new_acc}, new_acc}
            end)

          tagged
        end
      end
      """)
    end

    test "Enum.scan — like reduce but emits every intermediate accumulator" do
      assert_clean("""
      defmodule PrefixSum do
      def prefix_sums(nums), do: Enum.scan(nums, &Kernel.+/2)
      end
      """)
    end

    test "Enum.dedup_by — remove consecutive duplicates by key" do
      assert_clean("""
      defmodule EventDedup do
      def collapse_consecutive(events) do
      Enum.dedup_by(events, & &1.type)
      end
      end
      """)
    end

    test "Enum.min_max_by — single-pass extraction of both extremes" do
      assert_clean("""
      defmodule TemperatureRange do
      def range(readings) do
      {coldest, hottest} = Enum.min_max_by(readings, & &1.temp)
      {coldest.temp, hottest.temp}
      end
      end
      """)
    end

    test "Enum.find_value — find + transform in one step" do
      assert_clean("""
      defmodule FirstMatch do
        def first_even_squared(nums) do
          Enum.find_value(nums, fn num ->
            if rem(num, 2) == 0, do: num * num
          end)
        end
      end
      """)
    end

    test "Enum.split_with — partition into two lists by predicate" do
      assert_clean("""
      defmodule Partitioner do
        def adults_and_minors(people) do
          {adults, minors} = Enum.split_with(people, fn person -> person.age >= 18 end)
          %{adults: adults, minors: minors}
        end
      end
      """)
    end

    test "Enum.unzip — transpose a list of 2-tuples into two lists" do
      assert_clean("""
      defmodule Columns do
        def split_pairs(pairs) do
          {keys, values} = Enum.unzip(pairs)
          %{keys: keys, values: values}
        end
      end
      """)
    end

    test "Enum.into — collect into any collectable" do
      assert_clean("""
      defmodule Transformer do
        def invert(map) do
          Enum.into(map, %{}, fn {key, value} -> {value, key} end)
        end
      end
      """)
    end

    test "Enum.reject — remove elements that match a predicate" do
      assert_clean("""
      defmodule Cleaner do
        def remove_blanks(strings) do
          Enum.reject(strings, &(String.trim(&1) == ""))
        end
      end
      """)
    end

    test "Enum.map_intersperse — map and intersperse a separator in one pass" do
      assert_clean("""
      defmodule CsvRow do
        def to_iodata(fields) do
          Enum.map_intersperse(fields, ",", &to_string/1)
        end
      end
      """)
    end

    test "" do
      assert_clean("""
      defmodule VowelCounter do
        @vowels ~w(a e i o u)

        def count_vowels(text) do
          text
          |> String.downcase()
          |> do_count(0)
        end

        defp do_count(string, acc) do
          case String.next_grapheme(string) do
            {grapheme, rest} ->
              do_count(rest, if(grapheme in @vowels, do: acc + 1, else: acc))

            nil ->
              acc
          end
        end
      end
      """)
    end

    test "Stream.unfold — generate a (possibly infinite) sequence from a seed" do
      assert_clean("""
        defmodule FibStream do
          def stream do
            Stream.unfold({current, next}, fn {current, next} ->
              {current, {next, current + next}}
            end)
          end

          def first(count) do
            stream() |> Enum.take(count)
          end
        end
      """)
    end

    test "Stream.iterate — simpler unfold when the emitted value *is* the state" do
      assert_clean("""
      defmodule Powers do
        def powers_of_two(count) do
          Stream.iterate(1, &(&1 * 2)) |> Enum.take(count)
        end
      end
      """)
    end

    test "Stream.chunk_every + lazy pipeline — process a large file in batches without loading it all" do
      assert_clean("""
      defmodule BatchProcessor do
        def process_in_batches(stream, batch_size) do
          stream
          |> Stream.chunk_every(batch_size)
          |> Stream.map(&process_batch/1)
          |> Enum.to_list()
        end

        defp process_batch(batch), do: Enum.sum(batch)
      end
      """)
    end

    test "Stream.take_while — lazily consume while a predicate holds" do
      assert_clean("""
      defmodule Threshold do
        def take_below(sorted_nums, limit) do
          sorted_nums
          |> Stream.take_while(&(&1 < limit))
          |> Enum.to_list()
        end
      end
      """)
    end

    test "BinaryTree inorder traversal" do
      assert_clean("""
        defmodule BinaryTree do
          defstruct value: nil, left: nil, right: nil

          def inorder(tree), do: do_inorder(tree, [])

          defp do_inorder(nil, acc), do: acc
          defp do_inorder(%__MODULE__{left: left, value: value, right: right}, acc) do
            acc
            |> do_inorder(right)
            |> then(fn acc -> [value | acc] end)
            |> do_inorder(left)
          end

          def depth(nil), do: 0
          def depth(%__MODULE__{left: left, right: right}) do
            1 + max(depth(left), depth(right))
          end
        end
      """)
    end

    test "BFS with a queue (`:queue`)" do
      assert_clean("""
      defmodule BFS do
        def levels(nil), do: []

        def levels(root) do
          bfs(:queue.in(root, :queue.new()), [])
        end

        defp bfs(queue, acc) do
          case :queue.out(queue) do
          {:empty, _} ->
            Enum.reverse(acc)

          {{:value, nil}, rest} ->
            bfs(rest, acc)

          {{:value, %{value: v, left: l, right: r}}, rest} ->
            rest = :queue.in(l, :queue.in(r, rest))
            bfs(rest, [v | acc])
          end
        end
      end
      """)
    end

    test "Flatten via body-recursion with pattern matching" do
      assert_clean("""
        defmodule DeepFlatten do
          def flatten(list), do: list |> do_flatten([]) |> Enum.reverse()

          defp do_flatten([], acc), do: acc
          defp do_flatten([head | tail], acc) when is_list(head),
            do: do_flatten(head, do_flatten(tail, acc))
          defp do_flatten([head | tail], acc),
            do: do_flatten(tail, [head | acc])
        end
      """)
    end

    test "Recursive permutations" do
      assert_clean("""
      defmodule Permutations do
        def of([]), do: [[]]

        def of(list) do
          for elem <- list, rest <- of(list -- [elem]) do
            [elem | rest]
          end
        end
      end
      """)
    end

    test "`for` comprehensions" do
      assert_clean("""
        defmodule Comprehensions do
          # Cartesian product with filter
          def pythagorean_triples(max_value) do
            for first_number <- 1..max_value,
                second_number <- first_number..max_value,
                hypotenuse = :math.sqrt(first_number * first_number + second_number * second_number),
                hypotenuse == trunc(hypotenuse) and hypotenuse <= max_value do
              {first_number, second_number, trunc(hypotenuse)}
            end
          end

          # into: to build a map
          def index_by(records, key_function) do
            for record <- records, into: %{} do
              {key_function.(record), record}
            end
          end

          # uniq: to deduplicate (Elixir 1.14+)
          def unique_words(text) do
            for word <- String.split(text), uniq: true do
              String.downcase(word)
            end
          end

          # reduce: to fold inside a comprehension (Elixir 1.15+)
          def sum_squares(numbers) do
            for number <- numbers, reduce: 0 do
              accumulator -> accumulator + number * number
            end
          end
        end
      """)
    end

    test "`Map.new` — build a map from an enumerable with a transform function" do
      assert_clean("""
      defmodule Lookup do
        def by_id(records), do: Map.new(records, fn record -> {record.id, record} end)
      end
      """)
    end

    test "`Map.merge/3` — merge with conflict resolution. Great for combining frequency maps" do
      assert_clean("""
      defmodule FreqMerge do
        def merge_counts(left, right) do
          Map.merge(left, right, fn _key, existing_count, incoming_count -> existing_count + incoming_count end)
        end
      end
      """)
    end

    test "`Map.filter` / `Map.reject` (Elixir 1.13+)" do
      assert_clean("""
      defmodule MapOps do
        def high_scores(scores, threshold) do
          Map.filter(scores, fn {_name, score} -> score >= threshold end)
        end
      end
      """)
    end

    test "Keyword, Tuple, and Agent patterns 2" do
      assert_clean("""
      defmodule TupleSwap do
        def swap({elem1, elem2}), do: {elem2, elem1}

        def rotate3({elem1, elem2, elem3}), do: {elem2, elem3, elem1}
      end
      """)
    end

    test "String / binary utilities not yet shown" do
      assert_clean("""
      defmodule StringUtils do
        # String.starts_with? / String.ends_with? for validation
        def email?(str), do: String.contains?(str, "@") and not String.starts_with?(str, "@")

        # String.pad_leading for formatting
        def zero_pad(num, width), do: num |> Integer.to_string() |> String.pad_leading(width, "0")

        # String.to_integer with safe fallback
        def safe_int(str) do
          case Integer.parse(str) do
            {num, ""} -> {:ok, num}
            _ -> :error
          end
        end

        # String.slice for truncation
        def truncate(str, max_length) do
          if String.length(str) > max_length, do: String.slice(str, 0, max_length) <> "…", else: str
        end
      end
      """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS
  # ═══════════════════════════════════════════════════════════════════

  describe "fix works" do
    test "applies fixable rules and reports remaining issues" do
      input = """
      defmodule Foo do
        @doc false
        defp helper(bar), do: bar + 1
      end
      """

      result = Credence.fix(input)

      refute result.code =~ "@doc false"
      assert result.issues == []
    end
  end

  describe "fix integration — multi-rule showcase" do
    @showcase_input """
    defmodule Solution do
      @moduledoc "Provides text analysis utilities for processing and analyzing strings.\\n"
      @doc "Analyzes the given text and returns a map of statistics.\\n\\nReturns word count, character count, average word length,\\nfrequency map, and other derived metrics.\\n"
      @spec analyze(String.t()) :: map()
      def analyze(text) do
        words = String.split(text)

        if length(words) == 0 do
          %{words: 0, chars: 0, avg_length: 0.0}
        else
          char_count = String.graphemes(text) |> length()

          total_length = Enum.map(words, fn w -> String.length(w) end) |> Enum.sum()
          avg_length = total_length / Enum.count(words) * 1.0

          frequencies = Enum.reduce(words, %{}, fn word, acc ->
            Map.update(acc, String.downcase(word), 1, &(&1 + 1))
          end)

          sorted_desc = Enum.sort(words) |> Enum.reverse()
          top_3 = Enum.sort(words) |> Enum.take(-3)

          last = Enum.at(sorted_desc, -1)
          second_last = Enum.at(sorted_desc, -2)

          unique_words = words |> Enum.uniq_by(fn w -> w end)
          unique_csv = Enum.map(unique_words, fn w -> String.upcase(w) end) |> Enum.join(",")

          %{
            char_count: char_count,
            avg_length: avg_length,
            frequencies: frequencies,
            top_3: top_3,
            last: last,
            second_last: second_last,
            unique_csv: unique_csv,
            palindrome: is_palindrome(text)
          }
        end
      end

      def is_palindrome(text) do
        cleaned = text |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
        reversed = String.graphemes(cleaned) |> Enum.reverse() |> Enum.join("")
        cleaned |> Kernel.==(reversed)
      end

      @doc false
      defp normalize_words([], acc), do: Enum.reverse(acc)
      defp normalize_words([h | t], acc), do: normalize_words(t, acc ++ [String.downcase(h)])
    end
    """

    setup do
      %{result: Credence.fix(@showcase_input, [])}
    end

    # ─── NoLengthComparisonForEmpty ─────────────────────────────────

    test "replaces length(words) == 0 with words == []", %{result: %{code: code}} do
      assert code =~ "words == []"
      refute code =~ "length(words) == 0"
    end

    # ─── AvoidGraphemesLength ───────────────────────────────────────

    test "replaces String.graphemes |> length with String.length", %{result: %{code: code}} do
      assert code =~ "String.length(text)"
      refute code =~ "String.graphemes(text) |> length()"
    end

    # ─── NoEnumCountForLength ───────────────────────────────────────

    test "replaces Enum.count(words) with length(words)", %{result: %{code: code}} do
      assert code =~ "length(words)"
      refute code =~ "Enum.count(words)"
    end

    # ─── NoMultiplyByOnePointZero ───────────────────────────────────

    test "removes * 1.0", %{result: %{code: code}} do
      refute code =~ "* 1.0"
    end

    # ─── NoManualFrequencies ────────────────────────────────────────

    test "replaces manual frequency reduce with Enum.frequencies", %{result: %{code: code}} do
      assert code =~ "Enum.frequencies"
      refute code =~ "Map.update(acc"
    end

    # ─── NoSortThenReverse ──────────────────────────────────────────

    test "replaces Enum.sort |> Enum.reverse with Enum.sort(:desc)", %{result: %{code: code}} do
      assert code =~ "Enum.sort(words, :desc)"
      refute code =~ "Enum.sort(words) |> Enum.reverse()"
    end

    # ─── NoEnumAtNegativeIndex ──────────────────────────────────────

    test "groups negative Enum.at calls into reverse + pattern match",
         %{result: %{code: code}} do
      assert code =~ "Enum.reverse(sorted_desc)"
      assert code =~ "[last, second_last | _]"
      refute code =~ "Enum.at(sorted_desc, -1)"
      refute code =~ "Enum.at(sorted_desc, -2)"
    end

    # ─── NoIdentityFunctionInEnum ───────────────────────────────────

    test "simplifies Enum.uniq_by(fn w -> w end) to Enum.uniq()", %{result: %{code: code}} do
      assert code =~ "Enum.uniq()"
      refute code =~ "Enum.uniq_by"
    end

    # ─── UseMapJoin ─────────────────────────────────────────────────

    test "replaces Enum.map |> Enum.join with Enum.map_join", %{result: %{code: code}} do
      assert code =~ "Enum.map_join"
      refute Regex.match?(~r/Enum\.map\(.*\) \|> Enum\.join/, code)
    end

    # ─── NoIsPrefixForNonGuard ──────────────────────────────────────

    test "renames is_palindrome to palindrome? in def and call site",
         %{result: %{code: code}} do
      assert code =~ "def palindrome?(text)"
      assert code =~ "palindrome?(text)"
      refute code =~ "is_palindrome"
    end

    # ─── NoKernelOpInPipeline ───────────────────────────────────────

    test "extracts Kernel.== from pipeline to infix", %{result: %{code: code}} do
      assert code =~ "cleaned == reversed"
      refute code =~ "Kernel.=="
    end

    # ─── NoDocFalseOnPrivate ────────────────────────────────────────

    test "removes @doc false on private function", %{result: %{code: code}} do
      refute code =~ "@doc false"
    end

    # ─── NoRedundantEnumJoinSeparator ───────────────────────────────

    test "removes empty string from Enum.join", %{result: %{code: code}} do
      refute code =~ ~S|Enum.join("")|
    end

    # ─── Sanity checks ─────────────────────────────────────────────

    test "output compiles without errors", %{result: %{code: code}} do
      assert {:ok, _ast} = Code.string_to_quoted(code)
    end

    test "some unfixable rules still detected in remaining issues", %{result: %{issues: issues}} do
      distinct_rules = issues |> Enum.map(& &1.rule) |> Enum.uniq()
      assert length(distinct_rules) >= 2
    end
  end
end
