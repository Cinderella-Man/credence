defmodule Credence.Pattern.NoNestedEnumOnSameEnumerableTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoNestedEnumOnSameEnumerable.check(ast, [])
  end

  defp fix(source) do
    Credence.Pattern.NoNestedEnumOnSameEnumerable.fix(source, [])
  end

  describe "check/2" do
    test "detects member? inside map" do
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
      assert %Issue{} = issue
      assert issue.rule == :no_nested_enum_on_same_enumerable
      assert issue.message =~ "MapSet"
      assert issue.message =~ "O(n²)"
    end

    test "does not flag different enumerables" do
      code = """
      defmodule Good do
        def process(a, b) do
          Enum.map(a, fn x ->
            Enum.member?(b, x)
          end)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix/2" do
    test "basic: member? inside map" do
      source = "Enum.map(list, fn x -> Enum.member?(list, x) end)"
      result = fix(source)
      assert result =~ "set = MapSet.new(list)"
      assert result =~ "MapSet.member?(set, x)"
      refute result =~ "Enum.member?"
    end

    test "multi-line def with member? inside map" do
      source = """
      defmodule Example do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.member?(list, x + 1)
          end)
        end
      end
      """

      result = fix(source)
      assert result =~ "set = MapSet.new(list)"
      assert result =~ "MapSet.member?(set, x + 1)"
      refute result =~ "Enum.member?"
    end

    test "different variable name" do
      source = "Enum.map(items, fn i -> Enum.member?(items, i * 2) end)"
      result = fix(source)
      assert result =~ "set = MapSet.new(items)"
      assert result =~ "MapSet.member?(set, i * 2)"
    end

    test "member? with complex second argument" do
      source = "Enum.map(list, fn x -> Enum.member?(list, x.key) end)"
      result = fix(source)
      assert result =~ "MapSet.member?(set, x.key)"
    end

    test "inside a function definition (single-line lambda preserved)" do
      source = """
      defmodule Example do
        def run(list) do
          Enum.map(list, fn x -> Enum.member?(list, x) end)
        end
      end
      """

      result = fix(source)
      assert result =~ "set = MapSet.new(list)"
      assert result =~ "MapSet.member?(set, x)"
    end

    test "member? inside an if block" do
      source =
        "Enum.map(list, fn x -> if Enum.member?(list, x), do: x, else: nil end)"

      result = fix(source)
      assert result =~ "MapSet.member?(set, x)"
      assert result =~ "MapSet.new(list)"
    end

    test "returns source unchanged when no member? pattern found" do
      source = """
      defmodule Example do
        def run(list) do
          Enum.map(list, fn x -> x + 1 end)
        end
      end
      """

      assert fix(source) == source
    end

    test "returns source unchanged for Enum.count pattern (not fixable)" do
      source = """
      defmodule Example do
        def run(list) do
          Enum.map(list, fn x ->
            Enum.count(list)
          end)
        end
      end
      """

      assert fix(source) == source
    end
  end
end
