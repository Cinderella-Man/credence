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
    test "fixes basic pipeline: Enum.map |> Enum.max" do
      code = """
      list |> Enum.map(&String.length/1) |> Enum.max()
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "el"
      assert result =~ "best"
      assert result =~ "max("
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
      assert result =~ "acc"
      assert result =~ "+"
      assert result =~ "byte_size(el)"
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
      assert result =~ "el * el"
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
      refute result =~ "Enum.map"
    end

    test "fix with destructuring pattern uses pattern in reduce head, not fn application" do
      code = """
      map
      |> Enum.map(fn {_key, count} -> div(count * (count - 1), 2) end)
      |> Enum.sum()
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      # Should use pattern directly in reduce function head
      assert result =~ "{_key, count}"
      # Should NOT generate anonymous function application (fn ... end).(el)
      refute result =~ "(fn", "Expected pattern in reduce head, got anonymous function application"
    end

    test "fixes pipeline with capture syntax" do
      code = """
      strings |> Enum.map(&byte_size/1) |> Enum.sum()
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "byte_size(el)"
      refute result =~ "Enum.map"
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

    test "fixed code is valid Elixir" do
      code = """
      numbers
      |> Enum.chunk_every(k, 1, :discard)
      |> Enum.map(&Enum.sum/1)
      |> Enum.max()
      """

      result = fix(code)
      assert {:ok, _ast} = Sourceror.parse_string(result)
    end

    test "fixed sum code is valid Elixir" do
      code = """
      shapes
      |> Enum.map(&area/1)
      |> Enum.sum()
      """

      result = fix(code)
      assert {:ok, _ast} = Sourceror.parse_string(result)
    end

    test "fixed anonymous function code is valid Elixir" do
      code = """
      Enum.sum(Enum.map(list, fn x -> x * x end))
      """

      result = fix(code)
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
        def compute(items, dim) do
          weighted =
            items
            |> Enum.map(fn item ->
              Enum.at(item.weights, dim, 0)
            end)
            |> Enum.sum()

          {:ok, weighted}
        end
      end
      """

      output = fix(input)

      assert output =~ "defmodule Test do\n"
      assert output =~ "  def compute(items, dim) do\n"
      assert output =~ "    weighted =\n"
      # Blank line and return-tuple line untouched.
      assert output =~ "\n\n    {:ok, weighted}\n"
      assert output =~ "  end\nend\n"
      assert {:ok, _} = Sourceror.parse_string(output)
    end

    test "keeps the replacement multi-line when the original pipeline was multi-line" do
      input = """
      defmodule Test do
        def compute(items, dim) do
          items
          |> Enum.map(fn item -> Enum.at(item.weights, dim, 0) end)
          |> Enum.sum()
        end
      end
      """

      output = fix(input)

      # The fn body should not collapse onto the same line as `fn el, acc ->`.
      refute output =~ ~r/fn el, acc -> [^\n]*end\)/,
             "fn body collapsed to one line — expected newline after `->`:\n#{output}"

      assert output =~ "|> Enum.reduce("
      assert {:ok, _} = Sourceror.parse_string(output)
    end
  end

  describe "NoMapThenAggregate fix — closure-parameter substitution (issue: c.delivery survives)" do
    test "substitutes closure parameter through a dot-access in the body" do
      input = """
      clients |> Enum.map(fn c -> Enum.at(c.delivery, dim, 0) end) |> Enum.sum()
      """

      output = fix(input)

      assert {:ok, _} = Sourceror.parse_string(output)
      refute output =~ ~r/\bc\.delivery\b/
      assert output =~ ~r/\bel\.delivery\b/
    end

    test "substitutes closure parameter through a chained dot-access (r.inner.field)" do
      input = """
      records |> Enum.map(fn r -> r.inner.field end) |> Enum.sum()
      """

      output = fix(input)

      assert {:ok, _} = Sourceror.parse_string(output)
      refute output =~ ~r/\br\.inner\b/
      assert output =~ ~r/\bel\.inner\.field\b/
    end

    test "substitutes closure parameter inside a remote-call argument" do
      input = """
      strings |> Enum.map(fn s -> String.length(s) end) |> Enum.sum()
      """

      output = fix(input)

      assert {:ok, _} = Sourceror.parse_string(output)
      assert output =~ ~r/\bString\.length\(el\)/
      refute output =~ ~r/\bString\.length\(s\)/
    end

    test "full module repro from the GitHub issue compiles" do
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

      assert {:ok, _} = Sourceror.parse_string(output)
      refute output =~ ~r/\bc\.delivery\b/
    end
  end
end
