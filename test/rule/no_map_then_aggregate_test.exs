defmodule Credence.Rule.NoMapThenAggregateTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoMapThenAggregate.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoMapThenAggregate.fix(code, [])
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
  end

  describe "NoMapThenAggregate fix" do
    test "fixes basic pipeline: Enum.map |> Enum.max" do
      code = """
      list |> Enum.map(&String.length/1) |> Enum.max()
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "_el"
      assert result =~ "_best"
      assert result =~ "max("
      assert result =~ "apply"
      assert result =~ "String.length"
      refute result =~ "Enum.map"
    end

    test "fixes basic pipeline: Enum.map |> Enum.min" do
      code = """
      list |> Enum.map(&String.length/1) |> Enum.min()
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "min("
      refute result =~ "Enum.map"
    end

    test "fixes basic pipeline: Enum.map |> Enum.sum" do
      code = """
      list |> Enum.map(&byte_size/1) |> Enum.sum()
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "0"
      assert result =~ "_acc"
      assert result =~ "+"
      refute result =~ "Enum.map"
    end

    test "fixes three-step pipeline with preceding step" do
      code = """
      numbers
      |> Enum.chunk_every(k, 1, :discard)
      |> Enum.map(&Enum.sum/1)
      |> Enum.max()
      """

      result = fix(code)
      assert result =~ "Enum.chunk_every"
      assert result =~ "Enum.reduce"
      assert result =~ "max("
      refute result =~ "Enum.map"
    end

    test "fixes two-step pipeline (explicit source)" do
      code = """
      Enum.map(list, &String.length/1) |> Enum.max()
      """

      result = fix(code)
      assert result =~ "Enum.reduce(list"
      assert result =~ "max("
      refute result =~ "Enum.map"
    end

    test "fixes direct nesting: Enum.max(Enum.map(enum, f))" do
      code = """
      Enum.max(Enum.map(list, &String.length/1))
      """

      result = fix(code)
      assert result =~ "Enum.reduce(list"
      assert result =~ "max("
      refute result =~ "Enum.max(Enum.map"
    end

    test "fixes direct nesting: Enum.sum(Enum.map(enum, f))" do
      code = """
      Enum.sum(Enum.map(list, fn x -> x * x end))
      """

      result = fix(code)
      assert result =~ "Enum.reduce(list"
      assert result =~ "0"
      assert result =~ "+"
      assert result =~ "apply"
      refute result =~ "Enum.sum(Enum.map"
    end

    test "fixes pipeline with anonymous function" do
      code = """
      readings
      |> Enum.map(fn {_, temp} -> temp end)
      |> Enum.max()
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "max("
      assert result =~ "fn {_, temp} -> temp end"
      refute result =~ "Enum.map"
    end

    test "fixes pipeline with capture syntax" do
      code = """
      strings |> Enum.map(&byte_size/1) |> Enum.sum()
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "apply"
      assert result =~ "byte_size"
      refute result =~ "Enum.map"
    end

    test "fix does not modify code without map-aggregate pattern" do
      code = """
      list |> Enum.map(&(&1 * 2)) |> Enum.filter(&(&1 > 0))
      """

      result = fix(code)
      {:ok, original_ast} = Code.string_to_quoted(code)
      {:ok, fixed_ast} = Code.string_to_quoted(result)
      assert original_ast == fixed_ast
    end

    test "fixed code is valid Elixir" do
      code = """
      numbers
      |> Enum.chunk_every(k, 1, :discard)
      |> Enum.map(&Enum.sum/1)
      |> Enum.max()
      """

      result = fix(code)
      assert {:ok, _ast} = Code.string_to_quoted(result)
    end

    test "fixed sum code is valid Elixir" do
      code = """
      shapes
      |> Enum.map(&area/1)
      |> Enum.sum()
      """

      result = fix(code)
      assert {:ok, _ast} = Code.string_to_quoted(result)
    end

    test "fixed anonymous function code is valid Elixir" do
      code = """
      Enum.sum(Enum.map(list, fn x -> x * x end))
      """

      result = fix(code)
      assert {:ok, _ast} = Code.string_to_quoted(result)
    end
  end
end
