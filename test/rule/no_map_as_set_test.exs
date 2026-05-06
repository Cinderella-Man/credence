defmodule Credence.Pattern.NoMapAsSetTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoMapAsSet.check(ast, [])
  end

  describe "NoMapAsSet" do
    test "fixable? returns false" do
      refute Credence.Pattern.NoMapAsSet.fixable?()
    end

    # --- POSITIVE CASES (should flag) ---

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
      assert issue.message =~ "MapSet"
      assert issue.message =~ "true"
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
      assert hd(issues).message =~ "false"
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

    test "detects Map.put with true in pipeline" do
      code = """
      map |> Map.put(key, true)
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects Map.put with false in pipeline" do
      code = """
      map |> Map.put(key, false)
      """

      issues = check(code)
      assert length(issues) == 1
    end

    # --- NEGATIVE CASES (should NOT flag) ---

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

    test "passes Map.put with variable value" do
      code = """
      Map.put(map, key, value)
      """

      assert check(code) == []
    end

    test "passes Map.put with string value" do
      code = """
      Map.put(map, key, "true")
      """

      assert check(code) == []
    end

    test "passes Map.put with nil value" do
      code = """
      Map.put(map, key, nil)
      """

      assert check(code) == []
    end

    test "passes Map.put with atom value" do
      code = """
      Map.put(map, key, :active)
      """

      assert check(code) == []
    end
  end
end
