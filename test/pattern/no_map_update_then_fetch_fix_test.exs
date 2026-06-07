defmodule Credence.Pattern.NoMapUpdateThenFetchFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMapUpdateThenFetch

  describe "fix" do
    test "fixes Map.update/4 followed by Map.fetch! (no-bang fetch, Map.put)" do
      input = """
      defmodule BadDoubleTraversal do
        def increment(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          val = Map.fetch!(map, key)
          {map, val}
        end
      end
      """

      expected = """
      defmodule BadDoubleTraversal do
        def increment(map, key) do
          val = case Map.fetch(map, key) do
            {:ok, v} -> (&(&1 + 1)).(v)
            :error -> 1
          end
          map = Map.put(map, key, val)
          {map, val}
        end
      end
      """

      assert fix(NoMapUpdateThenFetch, input) == expected
    end

    test "fixes Map.update!/3 followed by Map.get (Map.put + Map.fetch!)" do
      input = """
      defmodule BadUpdateBang do
        def process(counts, key) do
          counts = Map.update!(counts, key, &(&1 + 1))
          current = Map.get(counts, key)
          {counts, current}
        end
      end
      """

      expected = """
      defmodule BadUpdateBang do
        def process(counts, key) do
          current = (&(&1 + 1)).(Map.fetch!(counts, key))
          counts = Map.put(counts, key, current)
          {counts, current}
        end
      end
      """

      assert fix(NoMapUpdateThenFetch, input) == expected
    end

    test "fixes Map.update/4 followed by Map.get" do
      input = """
      defmodule UpdateThenGet do
        def increment(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          val = Map.get(map, key)
          {map, val}
        end
      end
      """

      expected = """
      defmodule UpdateThenGet do
        def increment(map, key) do
          val = case Map.fetch(map, key) do
            {:ok, v} -> (&(&1 + 1)).(v)
            :error -> 1
          end
          map = Map.put(map, key, val)
          {map, val}
        end
      end
      """

      assert fix(NoMapUpdateThenFetch, input) == expected
    end

    test "fixes with intervening code that doesn't reference the map variable" do
      input = """
      defmodule InterveningCode do
        def increment(map, key) do
          map = Map.update(map, key, 1, &(&1 + 1))
          IO.puts("Updated!")
          val = Map.fetch!(map, key)
          {map, val}
        end
      end
      """

      expected = """
      defmodule InterveningCode do
        def increment(map, key) do
          val = case Map.fetch(map, key) do
            {:ok, v} -> (&(&1 + 1)).(v)
            :error -> 1
          end
          map = Map.put(map, key, val)
          IO.puts("Updated!")
          {map, val}
        end
      end
      """

      assert fix(NoMapUpdateThenFetch, input) == expected
    end

    test "fixes multiple update+fetch pairs in the same function" do
      input = """
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

      expected = """
      defmodule MultiplePairs do
        def process(map) do
          vx = case Map.fetch(map, :x) do
            {:ok, v} -> (&(&1 + 1)).(v)
            :error -> 0
          end
          map = Map.put(map, :x, vx)
          vy = case Map.fetch(map, :y) do
            {:ok, v} -> (&(&1 * 2)).(v)
            :error -> 0
          end
          map = Map.put(map, :y, vy)
          {map, vx, vy}
        end
      end
      """

      assert fix(NoMapUpdateThenFetch, input) == expected
    end

    test "does not modify code without Map.update" do
      code = """
      defmodule GoodCode do
        def run(map, key), do: Map.get(map, key)
      end
      """

      assert fix(NoMapUpdateThenFetch, code) == code
    end

    test "does not modify code with only Map.update and no following fetch" do
      code = """
      defmodule UpdateOnly do
        def process(map, key) do
          Map.update(map, key, 1, &(&1 + 1))
        end
      end
      """

      assert fix(NoMapUpdateThenFetch, code) == code
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

      assert fix(NoMapUpdateThenFetch, code) == code
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

      assert fix(NoMapUpdateThenFetch, code) == code
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

      assert fix(NoMapUpdateThenFetch, code) == code
    end
  end
end
