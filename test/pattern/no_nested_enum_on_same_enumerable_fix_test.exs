defmodule Credence.Pattern.NoNestedEnumOnSameEnumerableFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoNestedEnumOnSameEnumerable

  defp fix(source) do
    Credence.RuleHelpers.apply_rule_fix(NoNestedEnumOnSameEnumerable, source, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix/2" do
    test "basic: member? inside map" do
      input = """
      Enum.map(list, fn x -> Enum.member?(list, x) end)
      """

      expected = """
      set = MapSet.new(list)
      Enum.map(list, fn x -> MapSet.member?(set, x) end)
      """

      assert fix(input) == expected
    end

    test "multi-line def with member? inside map" do
      input = """
      defmodule Example do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.member?(list, x + 1)
          end)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          set = MapSet.new(list)

          Enum.map(list, fn x ->
            MapSet.member?(set, x + 1)
          end)
        end
      end
      """

      assert fix(input) == expected
    end

    test "different variable name" do
      input = """
      Enum.map(items, fn i -> Enum.member?(items, i * 2) end)
      """

      expected = """
      set = MapSet.new(items)
      Enum.map(items, fn i -> MapSet.member?(set, i * 2) end)
      """

      assert fix(input) == expected
    end

    test "member? with complex second argument" do
      input = """
      Enum.map(list, fn x -> Enum.member?(list, x.key) end)
      """

      expected = """
      set = MapSet.new(list)
      Enum.map(list, fn x -> MapSet.member?(set, x.key) end)
      """

      assert fix(input) == expected
    end

    test "inside a function definition (single-line lambda preserved)" do
      input = """
      defmodule Example do
        def run(list) do
          Enum.map(list, fn x -> Enum.member?(list, x) end)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          set = MapSet.new(list)
          Enum.map(list, fn x -> MapSet.member?(set, x) end)
        end
      end
      """

      assert fix(input) == expected
    end

    test "member? inside an if block" do
      input = """
      Enum.map(list, fn x -> if Enum.member?(list, x), do: x, else: nil end)
      """

      expected = """
      set = MapSet.new(list)
      Enum.map(list, fn x -> if MapSet.member?(set, x), do: x, else: nil end)
      """

      assert fix(input) == expected
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
