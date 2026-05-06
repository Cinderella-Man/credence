defmodule Credence.Pattern.NoNestedEnumOnSameEnumerable.UnfixableTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoNestedEnumOnSameEnumerableUnfixable.check(ast, [])
  end

  describe "check/2" do
    test "detects filter inside map with specific advice" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.filter(list, fn y -> y > x end)
          end)
        end
      end
      """

      [issue] = check(code)
      assert %Issue{} = issue
      assert issue.rule == :no_nested_enum_on_same_enumerable_unfixable
      assert issue.message =~ "Enum.filter/2"
      assert issue.message =~ "O(n²)"
      assert issue.message =~ "Avoid filtering the same list repeatedly"
    end

    test "detects member? and suggests MapSet" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.member?(list, x + 1)
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "MapSet"
      assert issue.message =~ "O(n²)"
    end

    test "falls back to generic message for other Enum functions" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.count(list)
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Nested Enum.count"
      assert issue.message =~ "O(n²)"
    end

    test "does not flag different enumerables" do
      code = """
      defmodule Good do
        def process(a, b) do
          Enum.map(a, fn x ->
            Enum.filter(b, fn y -> y > x end)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects find_value inside map" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.find_value(list, fn y -> if y > x, do: y end)
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Nested Enum.find_value"
    end

    test "detects any? inside map" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.any?(list, fn y -> y == x end)
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Nested Enum.any?"
    end

    test "detects reduce inside map" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.reduce(list, 0, fn y, acc -> acc + y - x end)
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Nested Enum.reduce"
    end

    test "flags nested count with longer pipeline" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.filter(& &1 > 0)
          |> Enum.map(fn x ->
            Enum.count(list)
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Nested Enum.count"
    end
  end
end
