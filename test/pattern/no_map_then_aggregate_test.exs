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

    # ---- max/min/sum: idiomatic, NOT flagged ----

    test "does not flag Enum.map |> Enum.max in pipeline" do
      code = """
      defmodule Good do
        def max_sum(numbers, k) do
          numbers
          |> Enum.chunk_every(k, 1, :discard)
          |> Enum.map(&Enum.sum/1)
          |> Enum.max()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map |> Enum.min in pipeline" do
      code = """
      defmodule Good do
        def cheapest(items) do
          items
          |> Enum.map(& &1.price)
          |> Enum.min()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map |> Enum.sum in pipeline" do
      code = """
      defmodule Good do
        def total_area(shapes) do
          shapes
          |> Enum.map(&area/1)
          |> Enum.sum()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag two-step pipeline: Enum.map(list, f) |> Enum.max()" do
      code = """
      defmodule Good do
        def biggest(list) do
          Enum.map(list, &String.length/1) |> Enum.max()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag direct nesting: Enum.max(Enum.map(list, f))" do
      code = """
      defmodule Good do
        def biggest(list) do
          Enum.max(Enum.map(list, &String.length/1))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag direct nesting: Enum.sum(Enum.map(list, f))" do
      code = """
      defmodule Good do
        def total(list) do
          Enum.sum(Enum.map(list, fn x -> x * x end))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map |> Enum.max with anonymous function" do
      code = """
      defmodule Good do
        def hottest(readings) do
          readings
          |> Enum.map(fn {_, temp} -> temp end)
          |> Enum.max()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map |> Enum.sum with capture" do
      code = """
      defmodule Good do
        def total_length(strings) do
          strings |> Enum.map(&byte_size/1) |> Enum.sum()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map |> Enum.max with default" do
      code = """
      defmodule Good do
        def biggest(list) do
          list
          |> Enum.map(&String.length/1)
          |> Enum.max(0)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map |> Enum.min with default" do
      code = """
      defmodule Good do
        def smallest(list) do
          list
          |> Enum.map(&String.length/1)
          |> Enum.min(0)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag direct nesting with default: Enum.max(Enum.map(enum, f), default)" do
      code = """
      defmodule Good do
        def biggest(list) do
          Enum.max(Enum.map(list, &String.length/1), 0)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag direct nesting with default: Enum.min(Enum.map(enum, f), default)" do
      code = """
      defmodule Good do
        def smallest(list) do
          Enum.min(Enum.map(list, &String.length/1), 0)
        end
      end
      """

      assert check(code) == []
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
end
