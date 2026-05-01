defmodule Credence.Rule.NoMapAsSetTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoMapAsSet.check(ast, [])
  end

  describe "NoMapAsSet" do
    test "passes code using MapSet" do
      code = """
      defmodule Good do
        def dedup(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
            if MapSet.member?(seen, item) do
              {seen, acc}
            else
              {MapSet.put(seen, item), [item | acc]}
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Map.put with non-boolean values" do
      code = """
      defmodule Safe do
        def count(list) do
          Enum.reduce(list, %{}, fn item, acc ->
            Map.put(acc, item, Map.get(acc, item, 0) + 1)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Map.put(seen, key, true)" do
      code = """
      defmodule Bad do
        def dedup(list) do
          Enum.reduce(list, {%{}, []}, fn item, {seen, acc} ->
            if Map.has_key?(seen, item) do
              {seen, acc}
            else
              {Map.put(seen, item, true), [item | acc]}
            end
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_map_as_set
      assert issue.severity == :info
      assert issue.message =~ "MapSet"
      assert issue.meta.line != nil
    end

    test "detects Map.put(seen, key, false)" do
      code = """
      defmodule Bad do
        def mark_absent(map, key) do
          Map.put(map, key, false)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "detects multiple boolean Map.put calls" do
      code = """
      defmodule Bad do
        def process(a, b, map) do
          map = Map.put(map, a, true)
          Map.put(map, b, true)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end
  end
end
