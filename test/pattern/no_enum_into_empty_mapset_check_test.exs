defmodule Credence.Pattern.NoEnumIntoEmptyMapsetCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEnumIntoEmptyMapset

  describe "flags" do
    test "Enum.into(enum, MapSet.new())" do
      code = """
      Enum.into(list, MapSet.new())
      """

      [issue] = check(NoEnumIntoEmptyMapset, code)
      assert issue.rule == :no_enum_into_empty_mapset
      assert issue.message =~ "MapSet.new"
    end

    test "Enum.into(enum, MapSet.new(), fun)" do
      code = """
      Enum.into(list, MapSet.new(), fn x -> x * 2 end)
      """

      [issue] = check(NoEnumIntoEmptyMapset, code)
      assert issue.rule == :no_enum_into_empty_mapset
      assert issue.message =~ "MapSet.new"
    end

    test "piped Enum.into(MapSet.new())" do
      code = """
      list |> Enum.into(MapSet.new())
      """

      [issue] = check(NoEnumIntoEmptyMapset, code)
      assert issue.rule == :no_enum_into_empty_mapset
    end

    test "piped Enum.into(MapSet.new(), fun)" do
      code = """
      list |> Enum.into(MapSet.new(), fn x -> x * 2 end)
      """

      [issue] = check(NoEnumIntoEmptyMapset, code)
      assert issue.rule == :no_enum_into_empty_mapset
    end

    test "Enum.into in a longer pipeline" do
      code = """
      routes
      |> Stream.with_index()
      |> Enum.into(MapSet.new(), fn {r, i} -> {i, r} end)
      """

      [issue] = check(NoEnumIntoEmptyMapset, code)
      assert issue.rule == :no_enum_into_empty_mapset
    end

    test "multiple occurrences" do
      code = """
      defmodule Bad do
        def build(data) do
          a = Enum.into(data, MapSet.new())
          b = Enum.into(other, MapSet.new(), fn x -> x end)
          {a, b}
        end
      end
      """

      issues = check(NoEnumIntoEmptyMapset, code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :no_enum_into_empty_mapset))
    end
  end

  describe "does not flag" do
    test "Enum.into with a non-empty/variable MapSet target" do
      code = """
      Enum.into(list, existing_set)
      """

      assert check(NoEnumIntoEmptyMapset, code) == []
    end

    test "Enum.into with a variable target and a transform fun" do
      code = """
      Enum.into(list, my_mapset, fn x -> x * 2 end)
      """

      assert check(NoEnumIntoEmptyMapset, code) == []
    end

    test "MapSet.new/1" do
      code = """
      MapSet.new(list)
      """

      assert check(NoEnumIntoEmptyMapset, code) == []
    end

    test "MapSet.new/2" do
      code = """
      MapSet.new(list, fn x -> x * 2 end)
      """

      assert check(NoEnumIntoEmptyMapset, code) == []
    end

    test "Enum.into with an empty map literal" do
      code = """
      Enum.into(list, %{})
      """

      assert check(NoEnumIntoEmptyMapset, code) == []
    end

    test "Enum.into with a list" do
      code = """
      Enum.into(map, [], fn {k, v} -> {k, v} end)
      """

      assert check(NoEnumIntoEmptyMapset, code) == []
    end

    test "Enum.into targeting MapSet.new(seed) with a seed argument" do
      code = """
      Enum.into(list, MapSet.new([0]))
      """

      assert check(NoEnumIntoEmptyMapset, code) == []
    end
  end
end
