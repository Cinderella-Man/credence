defmodule Credence.Rule.NoMapUpdateThenFetchTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoMapUpdateThenFetch.check(ast, [])
  end

  describe "NoMapUpdateThenFetch" do
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
      assert issue.severity == :warning
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
end
