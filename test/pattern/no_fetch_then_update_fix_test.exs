defmodule Credence.Pattern.NoFetchThenUpdateFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoFetchThenUpdate

  describe "rewrites the safe core" do
    test "Map.update! -> Map.put applying the captured fun to the bound value" do
      code = """
      defmodule Bad do
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

      expected = """
      defmodule Bad do
        def increment(map, key) do
          case Map.fetch(map, key) do
            {:ok, val} ->
              {val, Map.put(map, key, (&(&1 + 1)).(val))}

            :error ->
              {0, Map.put(map, key, 1)}
          end
        end
      end
      """

      confirm_fix(fix(NoFetchThenUpdate, code), expected)
    end

    test "Map.update/4 -> Map.put (default dropped, fun applied to bound value)" do
      code = """
      defmodule Bad do
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

      expected = """
      defmodule Bad do
        def increment(map, key) do
          case Map.fetch(map, key) do
            {:ok, n} ->
              Map.put(map, key, (&(&1 + n)).(n))

            :error ->
              Map.put(map, key, 0)
          end
        end
      end
      """

      confirm_fix(fix(NoFetchThenUpdate, code), expected)
    end

    test "literal atom key" do
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

      expected = """
      defmodule LiteralKey do
        def bump(map) do
          case Map.fetch(map, :count) do
            {:ok, n} -> {n, Map.put(map, :count, (&(&1 + 1)).(n))}
            :error -> {0, Map.put(map, :count, 1)}
          end
        end
      end
      """

      confirm_fix(fix(NoFetchThenUpdate, code), expected)
    end
  end

  describe "leaves dropped/unrelated shapes untouched" do
    test "no-op on a different map variable" do
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

      confirm_fix(fix(NoFetchThenUpdate, code), code)
    end

    test "no-op when the :ok value is bound to _" do
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

      confirm_fix(fix(NoFetchThenUpdate, code), code)
    end

    test "no-op when the branch rebinds the map" do
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

      confirm_fix(fix(NoFetchThenUpdate, code), code)
    end

    test "no-op when the fetched map is a non-simple expression" do
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

      confirm_fix(fix(NoFetchThenUpdate, code), code)
    end
  end
end
