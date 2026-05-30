defmodule Credence.Pattern.NoFetchThenUpdateTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoFetchThenUpdate

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoFetchThenUpdate.check(ast, [])
  end

  describe "check" do
    test "passes code with Map.put in the :ok branch" do
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

      assert check(code) == []
    end

    test "passes code using Map.get + Map.put without case/fetch" do
      code = """
      defmodule GoodCode do
        def increment(map, key) do
          val = Map.get(map, key, 0)
          Map.put(map, key, val + 1)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Map.update without a preceding Map.fetch" do
      code = """
      defmodule UpdateOnly do
        def increment(map, key) do
          Map.update!(map, key, &(&1 + 1))
        end
      end
      """

      assert check(code) == []
    end

    test "detects Map.update! inside case Map.fetch :ok branch" do
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

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_fetch_then_update
      assert issue.message =~ "Map.update"
      assert issue.message =~ "Map.put"
      assert issue.meta.line != nil
    end

    test "detects Map.update/4 inside case Map.fetch :ok branch" do
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

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_fetch_then_update
    end

    test "passes Map.update on a different map variable" do
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

      assert check(code) == []
    end

    test "passes Map.update on a different key" do
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

      assert check(code) == []
    end

    test "detects with tuple map access" do
      code = """
      defmodule TupleKey do
        def increment(map, key) do
          case Map.fetch(map, key) do
            {:ok, n} ->
              {n, Map.update!(map, key, &(&1 + 1))}

            :error ->
              {0, Map.put(map, key, 1)}
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "fix_patches returns empty list" do
      code = """
      defmodule Bad do
        def increment(map, key) do
          case Map.fetch(map, key) do
            {:ok, val} -> Map.update!(map, key, &(&1 + 1))
            :error -> Map.put(map, key, 1)
          end
        end
      end
      """

      ast = Sourceror.parse_string!(code)
      assert NoFetchThenUpdate.fix_patches(ast, source: code) == []
    end
  end
end
