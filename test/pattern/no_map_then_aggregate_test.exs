defmodule Credence.Pattern.NoMapThenAggregateTest do
  use ExUnit.Case

  alias Credence.Pattern.NoMapThenAggregate

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoMapThenAggregate.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoMapThenAggregate, code, [])
  end

  describe "NoMapThenAggregate check" do
    test "detects Enum.map |> Enum.max in pipeline" do
      code = """
      defmodule Bad do
        def max_sum(numbers, k) do
          numbers
          |> Enum.chunk_every(k, 1, :discard)
          |> Enum.map(&Enum.sum/1)
          |> Enum.max()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate
      assert issue.message =~ "Enum.map"
      assert issue.message =~ "Enum.max"
      # Message must NOT suggest unsafe Enum.reduce/2 (no initial value).
      # The accumulator would start as the raw first element, breaking when
      # the map function changes the element type.
      refute issue.message =~ "Enum.reduce(enum, fn",
             "Message must not suggest Enum.reduce/2 — use Enum.reduce/3 instead"
    end

    test "detects Enum.map |> Enum.min in pipeline" do
      code = """
      defmodule Bad do
        def cheapest(items) do
          items
          |> Enum.map(& &1.price)
          |> Enum.min()
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.min"
      refute issue.message =~ "Enum.reduce(enum, fn",
             "Message must not suggest Enum.reduce/2 — use Enum.reduce/3 instead"
    end

    test "detects Enum.map |> Enum.sum in pipeline" do
      code = """
      defmodule Bad do
        def total_area(shapes) do
          shapes
          |> Enum.map(&area/1)
          |> Enum.sum()
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.sum"
    end

    test "detects Enum.map |> Enum.max_by in pipeline" do
      code = """
      defmodule Bad do
        def row_with_most_ones(matrix) do
          matrix
          |> Enum.with_index()
          |> Enum.map(fn {row, index} -> {index, Enum.sum(row)} end)
          |> Enum.max_by(fn {_index, count} -> count end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate
      assert issue.message =~ "Enum.map"
      assert issue.message =~ "Enum.max_by"
    end

    test "detects Enum.map |> Enum.min_by in pipeline" do
      code = """
      defmodule Bad do
        def cheapest(items) do
          items
          |> Enum.map(fn item -> {item, item.price * item.qty} end)
          |> Enum.min_by(fn {_, total} -> total end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.min_by"
    end

    test "detects direct nesting: Enum.max_by(Enum.map(enum, f), g)" do
      code = """
      defmodule Bad do
        def biggest_by_length(list) do
          Enum.max_by(Enum.map(list, &String.length/1), fn len -> len end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max_by"
    end

    test "detects two-step pipeline: Enum.map(list, f) |> Enum.max()" do
      code = """
      defmodule Bad do
        def biggest(list) do
          Enum.map(list, &String.length/1) |> Enum.max()
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "detects direct nesting: Enum.max(Enum.map(list, f))" do
      code = """
      defmodule Bad do
        def biggest(list) do
          Enum.max(Enum.map(list, &String.length/1))
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "detects direct nesting: Enum.sum(Enum.map(list, f))" do
      code = """
      defmodule Bad do
        def total(list) do
          Enum.sum(Enum.map(list, fn x -> x * x end))
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.sum"
    end

    test "detects with anonymous function in map" do
      code = """
      defmodule Bad do
        def hottest(readings) do
          readings
          |> Enum.map(fn {_, temp} -> temp end)
          |> Enum.max()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate
    end

    test "detects with capture in map" do
      code = """
      defmodule Bad do
        def total_length(strings) do
          strings |> Enum.map(&byte_size/1) |> Enum.sum()
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.sum"
    end

    test "detects Enum.map |> Enum.max with default in pipeline" do
      code = """
      defmodule Bad do
        def biggest(list) do
          list
          |> Enum.map(&String.length/1)
          |> Enum.max(0)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate
      assert issue.message =~ "Enum.max"
    end

    test "detects Enum.map |> Enum.min with default in pipeline" do
      code = """
      defmodule Bad do
        def smallest(list) do
          list
          |> Enum.map(&String.length/1)
          |> Enum.min(0)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate
      assert issue.message =~ "Enum.min"
    end

    test "detects direct nesting with default: Enum.max(Enum.map(enum, f), default)" do
      code = """
      defmodule Bad do
        def biggest(list) do
          Enum.max(Enum.map(list, &String.length/1), 0)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate
      assert issue.message =~ "Enum.max"
    end

    test "detects direct nesting with default: Enum.min(Enum.map(enum, f), default)" do
      code = """
      defmodule Bad do
        def smallest(list) do
          Enum.min(Enum.map(list, &String.length/1), 0)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate
      assert issue.message =~ "Enum.min"
    end

    # ---- Negative cases ----

    test "does not flag Enum.map without aggregation" do
      code = """
      defmodule Good do
        def double(list) do
          Enum.map(list, &(&1 * 2))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.max without Enum.map" do
      code = """
      defmodule Good do
        def biggest(list), do: Enum.max(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.max_by without Enum.map" do
      code = """
      defmodule Good do
        def longest(strings), do: Enum.max_by(strings, &String.length/1)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.min_by without Enum.map" do
      code = """
      defmodule Good do
        def shortest(strings), do: Enum.min_by(strings, &String.length/1)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map piped into non-aggregate" do
      code = """
      defmodule Good do
        def process(list) do
          list
          |> Enum.map(&(&1 * 2))
          |> Enum.filter(&(&1 > 0))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce (correct single-pass approach)" do
      code = """
      defmodule Good do
        def max_sum(chunks) do
          Enum.reduce(chunks, fn chunk, best ->
            max(Enum.sum(chunk), best)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map piped into Enum.sort" do
      code = """
      defmodule Good do
        def sorted_lengths(strings) do
          strings |> Enum.map(&String.length/1) |> Enum.sort()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map with steps in between before aggregate" do
      code = """
      defmodule Good do
        def process(list) do
          list
          |> Enum.map(&(&1 * 2))
          |> Enum.filter(&(&1 > 0))
          |> Enum.max()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag non-Enum module map" do
      code = """
      defmodule Good do
        def process(list) do
          MyModule.map(list, &(&1 * 2)) |> Enum.max()
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.map |> MapSet.new in pipeline" do
      code = """
      defmodule Bad do
        def build_set(items) do
          items
          |> Enum.map(fn {_, v} -> v end)
          |> MapSet.new()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate
      assert issue.message =~ "MapSet.new"
      assert issue.message =~ "intermediate list"
    end

    test "detects Enum.map |> Map.new in pipeline" do
      code = """
      defmodule Bad do
        def build_map(pairs) do
          pairs
          |> Enum.map(fn {k, v} -> {k, v * 2} end)
          |> Map.new()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate
      assert issue.message =~ "Map.new"
    end

    test "detects direct nesting: MapSet.new(Enum.map(enum, f))" do
      code = """
      defmodule Bad do
        def build_set(list) do
          MapSet.new(Enum.map(list, &String.to_atom/1))
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "MapSet.new"
    end

    test "detects direct nesting: Map.new(Enum.map(enum, f))" do
      code = """
      defmodule Bad do
        def build_map(list) do
          Map.new(Enum.map(list, fn x -> {x, x * 2} end))
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Map.new"
    end

    test "does not flag MapSet.new without Enum.map" do
      code = """
      defmodule Good do
        def build_set(list), do: MapSet.new(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.new without Enum.map" do
      code = """
      defmodule Good do
        def build_map(list), do: Map.new(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag MapSet.new with transform only (no map)" do
      code = """
      defmodule Good do
        def build_set(list), do: MapSet.new(list, &String.to_atom/1)
      end
      """

      assert check(code) == []
    end
  end

  describe "NoMapThenAggregate fix" do
    test "Enum.map |> Enum.max is check-only (no auto-fix)" do
      code = """
      list |> Enum.map(&String.length/1) |> Enum.max()
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.max()"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map |> Enum.min is check-only (no auto-fix)" do
      code = """
      list |> Enum.map(&String.length/1) |> Enum.min()
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.min()"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map |> Enum.sum is check-only (no auto-fix)" do
      code = """
      list |> Enum.map(&byte_size/1) |> Enum.sum()
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.sum()"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map |> Enum.max with preceding step is check-only (no auto-fix)" do
      code = """
      numbers
      |> Enum.chunk_every(k, 1, :discard)
      |> Enum.map(&Enum.sum/1)
      |> Enum.max()
      """

      result = fix(code)
      assert result =~ "Enum.chunk_every"
      assert result =~ "Enum.map"
      assert result =~ "Enum.max()"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map |> Enum.max with explicit source is check-only (no auto-fix)" do
      code = """
      Enum.map(list, &String.length/1) |> Enum.max()
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.max()"
      refute result =~ "Enum.reduce"
    end

    test "Enum.max(Enum.map(enum, f)) is check-only (no auto-fix)" do
      code = """
      Enum.max(Enum.map(list, &String.length/1))
      """

      result = fix(code)
      assert result =~ "Enum.max"
      assert result =~ "Enum.map"
      refute result =~ "Enum.reduce"
    end

    test "Enum.sum(Enum.map(enum, f)) is check-only (no auto-fix)" do
      code = """
      Enum.sum(Enum.map(list, fn x -> x * x end))
      """

      result = fix(code)
      assert result =~ "Enum.sum"
      assert result =~ "Enum.map"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map |> Enum.max with anonymous function is check-only (no auto-fix)" do
      code = """
      readings
      |> Enum.map(fn {_, temp} -> temp end)
      |> Enum.max()
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.max()"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map with destructuring |> Enum.sum is check-only (no auto-fix)" do
      code = """
      map
      |> Enum.map(fn {_key, count} -> div(count * (count - 1), 2) end)
      |> Enum.sum()
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.sum()"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map with capture |> Enum.sum is check-only (no auto-fix)" do
      code = """
      strings |> Enum.map(&byte_size/1) |> Enum.sum()
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.sum()"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map |> Enum.max_by is check-only (no auto-fix)" do
      code = """
      matrix
      |> Enum.with_index()
      |> Enum.map(fn {row, index} -> {index, Enum.sum(row)} end)
      |> Enum.max_by(fn {_index, count} -> count end)
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.max_by"
    end

    test "Enum.map |> Enum.min_by is check-only (no auto-fix)" do
      code = """
      items
      |> Enum.map(fn item -> {item, item.price} end)
      |> Enum.min_by(fn {_, price} -> price end)
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.min_by"
    end

    test "fix does not modify code without map-aggregate pattern" do
      code = """
      list |> Enum.map(&(&1 * 2)) |> Enum.filter(&(&1 > 0))
      """

      result = fix(code)
      {:ok, original_ast} = Sourceror.parse_string(code)
      {:ok, fixed_ast} = Sourceror.parse_string(result)
      assert original_ast == fixed_ast
    end

    test "Enum.chunk_every |> Enum.map(&Enum.max/1) |> Enum.max() is check-only (regression from row 56351)" do
      code = """
      defmodule Solution do
        def maxgamescore(list, k) when k >= 1 do
          list
          |> Enum.chunk_every(k, 1, :discard)
          |> Enum.map(fn chunk -> Enum.max(chunk) end)
          |> Enum.max()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_map_then_aggregate

      result = fix(code)
      # Must NOT rewrite to Enum.reduce — the reduce/2 form would use the
      # raw first chunk (a list) as the accumulator, breaking max comparison.
      refute result =~ "Enum.reduce"
      assert result =~ "Enum.max()"
      assert result =~ "Enum.map"
    end

    test "Enum.map |> Enum.max(default) is check-only (no auto-fix)" do
      code = """
      list |> Enum.map(&String.length/1) |> Enum.max(0)
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.max(0)"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map |> Enum.min(default) is check-only (no auto-fix)" do
      code = """
      list |> Enum.map(&String.length/1) |> Enum.min(0)
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.min(0)"
      refute result =~ "Enum.reduce"
    end

    test "Enum.max(Enum.map(enum, f), default) is check-only (no auto-fix)" do
      code = """
      Enum.max(Enum.map(list, &String.length/1), 0)
      """

      result = fix(code)
      assert result =~ "Enum.map"
      assert result =~ "Enum.max"
      refute result =~ "Enum.reduce"
    end

    test "Enum.map |> Enum.max with sum is check-only — original preserved" do
      code = """
      numbers
      |> Enum.chunk_every(k, 1, :discard)
      |> Enum.map(&Enum.sum/1)
      |> Enum.max()
      """

      result = fix(code)
      # Check-only: fix returns original code unchanged
      assert result =~ "Enum.map"
      assert result =~ "Enum.max()"
      assert {:ok, _ast} = Sourceror.parse_string(result)
    end

    test "Enum.map |> Enum.sum is check-only — sum preserved" do
      code = """
      shapes
      |> Enum.map(&area/1)
      |> Enum.sum()
      """

      result = fix(code)
      # Check-only: fix returns original code unchanged
      assert result =~ "Enum.map"
      assert result =~ "Enum.sum()"
      refute result =~ "Enum.reduce"
      assert {:ok, _ast} = Sourceror.parse_string(result)
    end

    test "Enum.sum(Enum.map) is check-only — sum preserved" do
      code = """
      Enum.sum(Enum.map(list, fn x -> x * x end))
      """

      result = fix(code)
      # Check-only: fix returns original code unchanged
      assert result =~ "Enum.sum"
      assert result =~ "Enum.map"
      refute result =~ "Enum.reduce"
      assert {:ok, _ast} = Sourceror.parse_string(result)
    end

    test "fixes Enum.map |> MapSet.new pipeline" do
      code = """
      items |> Enum.map(fn {_, v} -> v end) |> MapSet.new()
      """

      result = fix(code)
      assert result =~ "MapSet.new"
      assert result =~ "fn {_, v} -> v end"
      refute result =~ "Enum.map"
    end

    test "fixes Enum.map |> Map.new pipeline" do
      code = """
      pairs |> Enum.map(fn {k, v} -> {k, v * 2} end) |> Map.new()
      """

      result = fix(code)
      assert result =~ "Map.new"
      refute result =~ "Enum.map"
    end

    test "fixes direct nesting: MapSet.new(Enum.map(enum, f))" do
      code = """
      MapSet.new(Enum.map(list, &String.to_atom/1))
      """

      result = fix(code)
      assert result =~ "MapSet.new(list"
      assert result =~ "String.to_atom"
      refute result =~ "Enum.map"
    end

    test "fixes direct nesting: Map.new(Enum.map(enum, f))" do
      code = """
      Map.new(Enum.map(list, fn x -> {x, x * 2} end))
      """

      result = fix(code)
      assert result =~ "Map.new(list"
      refute result =~ "Enum.map"
    end

    test "fixes three-step pipeline with constructor" do
      code = """
      edges
      |> Enum.map(fn [_, dest] -> dest end)
      |> MapSet.new()
      """

      result = fix(code)
      assert result =~ "MapSet.new"
      assert result =~ "fn [_, dest] -> dest end"
      refute result =~ "Enum.map"
      assert {:ok, _ast} = Sourceror.parse_string(result)
    end

    test "fixed MapSet.new code is valid Elixir" do
      code = """
      items
      |> Enum.filter(&active?/1)
      |> Enum.map(fn {_, v} -> v end)
      |> MapSet.new()
      """

      result = fix(code)
      assert result =~ "MapSet.new"
      assert {:ok, _ast} = Sourceror.parse_string(result)
    end
  end

  describe "NoMapThenAggregate fix — locality (issue: collapses multi-line pipes)" do
    test "preserves surrounding code byte-identically outside the change site" do
      input = """
      defmodule Test do
        def build_set(items, dim) do
          result =
            items
            |> Enum.map(fn item ->
              Enum.at(item.weights, dim, 0)
            end)
            |> MapSet.new()

          {:ok, result}
        end
      end
      """

      output = fix(input)

      assert output =~ "defmodule Test do\n"
      assert output =~ "  def build_set(items, dim) do\n"
      assert output =~ "    result =\n"
      # Blank line and return-tuple line untouched.
      assert output =~ "\n\n    {:ok, result}\n"
      assert output =~ "  end\nend\n"
      assert {:ok, _} = Sourceror.parse_string(output)
    end

    test "keeps the replacement multi-line when the original pipeline was multi-line" do
      input = """
      defmodule Test do
        def build_set(items, dim) do
          items
          |> Enum.map(fn item -> Enum.at(item.weights, dim, 0) end)
          |> MapSet.new()
        end
      end
      """

      output = fix(input)

      assert output =~ "MapSet.new(fn item ->"
      refute output =~ "Enum.map"
      assert {:ok, _} = Sourceror.parse_string(output)
    end
  end

  describe "NoMapThenAggregate fix — Enum.sum is check-only (no reduce rewrite)" do
    test "Enum.map |> Enum.sum with dot-access is check-only" do
      input = """
      clients |> Enum.map(fn c -> Enum.at(c.delivery, dim, 0) end) |> Enum.sum()
      """

      output = fix(input)

      # Check-only: code unchanged
      assert output =~ "Enum.map"
      assert output =~ "Enum.sum()"
      refute output =~ "Enum.reduce"
      assert {:ok, _} = Sourceror.parse_string(output)
    end

    test "Enum.map |> Enum.sum with chained dot-access is check-only" do
      input = """
      records |> Enum.map(fn r -> r.inner.field end) |> Enum.sum()
      """

      output = fix(input)

      assert output =~ "Enum.map"
      assert output =~ "Enum.sum()"
      refute output =~ "Enum.reduce"
      assert {:ok, _} = Sourceror.parse_string(output)
    end

    test "Enum.map |> Enum.sum with remote-call argument is check-only" do
      input = """
      strings |> Enum.map(fn s -> String.length(s) end) |> Enum.sum()
      """

      output = fix(input)

      assert output =~ "Enum.map"
      assert output =~ "Enum.sum()"
      refute output =~ "Enum.reduce"
      assert {:ok, _} = Sourceror.parse_string(output)
    end

    test "full module with Enum.sum is check-only" do
      input = """
      defmodule Test do
        def calc(clients, dim) do
          clients
          |> Enum.map(fn c -> Enum.at(c.delivery, dim, 0) end)
          |> Enum.sum()
        end
      end
      """

      output = fix(input)

      assert output =~ "Enum.map"
      assert output =~ "Enum.sum()"
      refute output =~ "Enum.reduce"
      assert {:ok, _} = Sourceror.parse_string(output)
    end
  end
end
