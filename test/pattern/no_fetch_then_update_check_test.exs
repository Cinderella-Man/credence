defmodule Credence.Pattern.NoFetchThenUpdateCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoFetchThenUpdate

  describe "flags the safe core" do
    test "Map.update! inside case Map.fetch :ok branch on same map and key" do
      code = """
      defmodule BadFetchThenUpdate do
        def increment(map, key) do
          case Map.fetch(map, key) do
            {:ok, val} ->
              {val, Map.update!(map, key, &(&1 + 1))}

            :error ->
              {0, Map.put(map, key, 1)}
          end
        end
      end
      """

      issues = check(NoFetchThenUpdate, code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_fetch_then_update
      assert issue.meta.line != nil
    end

    test "Map.update/4 inside case Map.fetch :ok branch on same map and key" do
      code = """
      defmodule BadFetchThenUpdate do
        def increment(map, key) do
          case Map.fetch(map, key) do
            {:ok, n} ->
              Map.update(map, key, 0, &(&1 + n))

            :error ->
              Map.put(map, key, 0)
          end
        end
      end
      """

      issues = check(NoFetchThenUpdate, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_fetch_then_update
    end

    test "flags with a literal atom key" do
      code = """
      defmodule LiteralKey do
        def bump(map) do
          case Map.fetch(map, :count) do
            {:ok, n} -> {n, Map.update!(map, :count, &(&1 + 1))}
            :error -> {0, Map.put(map, :count, 1)}
          end
        end
      end
      """

      assert length(check(NoFetchThenUpdate, code)) == 1
    end
  end

  describe "does not flag" do
    test "code already using Map.put in the :ok branch" do
      code = """
      defmodule GoodCode do
        def increment(map, key) do
          case Map.fetch(map, key) do
            {:ok, val} -> Map.put(map, key, val + 1)
            :error -> Map.put(map, key, 1)
          end
        end
      end
      """

      assert check(NoFetchThenUpdate, code) == []
    end

    test "Map.update without a preceding Map.fetch" do
      code = """
      defmodule UpdateOnly do
        def increment(map, key) do
          Map.update!(map, key, &(&1 + 1))
        end
      end
      """

      assert check(NoFetchThenUpdate, code) == []
    end

    test "Map.update on a different map variable" do
      code = """
      defmodule DifferentMap do
        def process(map_a, map_b, key) do
          case Map.fetch(map_a, key) do
            {:ok, val} -> Map.update!(map_b, key, &(&1 + 1))
            :error -> Map.put(map_a, key, 1)
          end
        end
      end
      """

      assert check(NoFetchThenUpdate, code) == []
    end

    test "Map.update on a different key" do
      code = """
      defmodule DifferentKey do
        def process(map, key_a, key_b) do
          case Map.fetch(map, key_a) do
            {:ok, val} -> Map.update!(map, key_b, &(&1 + 1))
            :error -> Map.put(map, key_a, 1)
          end
        end
      end
      """

      assert check(NoFetchThenUpdate, code) == []
    end

    # --- Deliberately dropped unsafe shapes (locked in as "no issue") ---

    test "no issue when the :ok value is bound to _ (value unavailable to reuse)" do
      code = """
      defmodule Underscore do
        def bump(map, key) do
          case Map.fetch(map, key) do
            {:ok, _} -> {0, Map.update!(map, key, &(&1 + 1))}
            :error -> {0, Map.put(map, key, 1)}
          end
        end
      end
      """

      assert check(NoFetchThenUpdate, code) == []
    end

    test "no issue when the branch rebinds the map (= makes the rewrite unsafe)" do
      code = """
      defmodule Rebinds do
        def bump(map, key) do
          case Map.fetch(map, key) do
            {:ok, n} ->
              map = reset(map)
              Map.update!(map, key, &(&1 + 1))

            :error ->
              Map.put(map, key, 1)
          end
        end
      end
      """

      assert check(NoFetchThenUpdate, code) == []
    end

    test "no issue when the update sits inside a nested fn" do
      code = """
      defmodule NestedFn do
        def bump(map, key) do
          case Map.fetch(map, key) do
            {:ok, n} ->
              Enum.map([1], fn _ -> Map.update!(map, key, &(&1 + n)) end)

            :error ->
              [Map.put(map, key, 1)]
          end
        end
      end
      """

      assert check(NoFetchThenUpdate, code) == []
    end

    test "no issue when the fetched map is a non-simple expression (call)" do
      code = """
      defmodule NonSimpleMap do
        def bump(key) do
          case Map.fetch(load_map(), key) do
            {:ok, n} -> {n, Map.update!(load_map(), key, &(&1 + 1))}
            :error -> {0, Map.put(load_map(), key, 1)}
          end
        end
      end
      """

      assert check(NoFetchThenUpdate, code) == []
    end
  end
end
