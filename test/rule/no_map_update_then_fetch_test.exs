defmodule Credence.Rule.NoMapUpdateThenFetchTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoMapUpdateThenFetch.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoMapUpdateThenFetch.fix(code, [])
  end

  describe "check" do
    test "passes code that uses Map.get then Map.put" do
      code = """
      defmodule GoodUpdate do
        def increment(map, key) do
          count = Map.get(map, key, 0) + 1
          new_map = Map.put(map, key, count)
          {new_map, count}
        end
      end
      """

      assert check(code) == []
    end

    test "passes Map.fetch! on a variable not from Map.update" do
      code = """
      defmodule SafeFetch do
        def get_value(map, key) do
          Map.fetch!(map, key)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Map.update followed by Map.fetch! on same variable" do
      code = """
      defmodule BadDoubleTraversal do
        def increment(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          val = Map.fetch!(map, key)
          {map, val}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_map_update_then_fetch
      assert issue.message =~ "map"
      assert issue.message =~ "Map.put/3"
      assert issue.meta.line != nil
    end

    test "detects Map.update! followed by Map.get on same variable" do
      code = """
      defmodule BadUpdateBang do
        def process(counts, key) do
          counts = Map.update!(counts, key, &(&1 + 1))
          current = Map.get(counts, key)
          {counts, current}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "counts"
    end

    test "ignores Map.fetch! on a different variable" do
      code = """
      defmodule DifferentVars do
        def process(map_a, map_b, key) do
          map_a = Map.update(map_a, key, 1, &(&1 + 1))
          val = Map.fetch!(map_b, key)
          {map_a, val}
        end
      end
      """

      assert check(code) == []
    end

    test "ignores Map.update without a following fetch" do
      code = """
      defmodule UpdateOnly do
        def process(map, key) do
          Map.update(map, key, 1, &(&1 + 1))
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "fixes Map.update/4 followed by Map.fetch!" do
      code = """
      defmodule BadDoubleTraversal do
        def increment(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          val = Map.fetch!(map, key)
          {map, val}
        end
      end
      """

      fixed = fix(code)
      assert {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Rule.NoMapUpdateThenFetch.check(ast, []) == []
    end

    test "fixes Map.update!/3 followed by Map.get" do
      code = """
      defmodule BadUpdateBang do
        def process(counts, key) do
          counts = Map.update!(counts, key, &(&1 + 1))
          current = Map.get(counts, key)
          {counts, current}
        end
      end
      """

      fixed = fix(code)
      assert {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Rule.NoMapUpdateThenFetch.check(ast, []) == []
    end

    test "fixes Map.update/4 followed by Map.get" do
      code = """
      defmodule UpdateThenGet do
        def increment(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          val = Map.get(map, key)
          {map, val}
        end
      end
      """

      fixed = fix(code)
      assert {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Rule.NoMapUpdateThenFetch.check(ast, []) == []
    end

    test "fixes with intervening code that doesn't reference the map variable" do
      code = """
      defmodule InterveningCode do
        def increment(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          IO.puts("Updated!")
          val = Map.fetch!(map, key)
          {map, val}
        end
      end
      """

      fixed = fix(code)
      assert {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Rule.NoMapUpdateThenFetch.check(ast, []) == []
    end

    test "fixes multiple update+fetch pairs in the same function" do
      code = """
      defmodule MultiplePairs do
        def process(map) do
          map = Map.update(map, :x, 0, &(&1 + 1))
          vx = Map.fetch!(map, :x)
          map = Map.update(map, :y, 0, &(&1 * 2))
          vy = Map.get(map, :y)
          {map, vx, vy}
        end
      end
      """

      fixed = fix(code)
      assert {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Rule.NoMapUpdateThenFetch.check(ast, []) == []
    end

    test "produces valid Elixir code" do
      code = """
      defmodule BadDoubleTraversal do
        def increment(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          val = Map.fetch!(map, key)
          {map, val}
        end
      end
      """

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
    end

    test "fixed update/4 replacement uses Map.put and Map.fetch (no bang)" do
      code = """
      defmodule BadDoubleTraversal do
        def increment(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          val = Map.fetch!(map, key)
          {map, val}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Map.put"
      assert fixed =~ "Map.fetch"
      refute fixed =~ "Map.update"
      refute fixed =~ "Map.fetch!"
    end

    test "fixed update!/3 replacement uses Map.put and Map.fetch!" do
      code = """
      defmodule BadUpdateBang do
        def process(counts, key) do
          counts = Map.update!(counts, key, &(&1 + 1))
          current = Map.get(counts, key)
          {counts, current}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Map.put"
      assert fixed =~ "Map.fetch!"
      refute fixed =~ "Map.update!"
      refute fixed =~ "Map.get("
    end

    test "does not modify code without Map.update" do
      code = """
      defmodule GoodCode do
        def run(map, key), do: Map.get(map, key)
      end
      """

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
    end

    test "does not modify code with only Map.update and no following fetch" do
      code = """
      defmodule UpdateOnly do
        def process(map, key) do
          Map.update(map, key, 1, &(&1 + 1))
        end
      end
      """

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
    end

    test "does not modify when fetch is on a different variable" do
      code = """
      defmodule DifferentVars do
        def process(map_a, map_b, key) do
          map_a = Map.update(map_a, key, 1, &(&1 + 1))
          val = Map.fetch!(map_b, key)
          {map_a, val}
        end
      end
      """

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      assert fixed =~ "Map.update"
    end

    test "does not modify when fetch is on a different key" do
      code = """
      defmodule DifferentKeys do
        def process(map) do
          map = Map.update(map, :x, 0, &(&1 + 1))
          val = Map.fetch!(map, :y)
          {map, val}
        end
      end
      """

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      assert fixed =~ "Map.update"
    end

    test "does not modify when intervening code references the map variable" do
      code = """
      defmodule InterveningRef do
        def process(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          map = Map.put(map, :other, 99)
          val = Map.fetch!(map, key)
          {map, val}
        end
      end
      """

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      assert fixed =~ "Map.update"
    end
  end
end
