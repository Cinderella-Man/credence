defmodule Credence.Pattern.NoEnumIntoEmptyMapsetTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumIntoEmptyMapset

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEnumIntoEmptyMapset.check(ast, [])
  end

  defp fix(code), do: Credence.RuleHelpers.apply_rule_fix(NoEnumIntoEmptyMapset, code, [])

  describe "check" do
    test "detects Enum.into(enum, MapSet.new())" do
      code = """
      Enum.into(list, MapSet.new())
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_mapset
      assert issue.message =~ "MapSet.new"
    end

    test "detects Enum.into(enum, MapSet.new(), fun)" do
      code = """
      Enum.into(list, MapSet.new(), fn x -> x * 2 end)
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_mapset
      assert issue.message =~ "MapSet.new"
    end

    test "detects piped Enum.into(MapSet.new())" do
      code = """
      list |> Enum.into(MapSet.new())
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_mapset
    end

    test "detects piped Enum.into(MapSet.new(), fun)" do
      code = """
      list |> Enum.into(MapSet.new(), fn x -> x * 2 end)
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_mapset
    end

    test "detects Enum.into in a longer pipeline" do
      code = """
      routes
      |> Stream.with_index()
      |> Enum.into(MapSet.new(), fn {r, i} -> {i, r} end)
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_mapset
    end

    test "detects multiple occurrences" do
      code = """
      defmodule Bad do
        def build(data) do
          a = Enum.into(data, MapSet.new())
          b = Enum.into(other, MapSet.new(), fn x -> x end)
          {a, b}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :no_enum_into_empty_mapset))
    end

    # ── Negative cases ──────────────────────────────────────────

    test "does not flag Enum.into with non-empty MapSet" do
      code = """
      Enum.into(list, existing_set)
      """

      assert check(code) == []
    end

    test "does not flag Enum.into with a variable MapSet" do
      code = """
      Enum.into(list, my_mapset, fn x -> x * 2 end)
      """

      assert check(code) == []
    end

    test "does not flag MapSet.new/1" do
      code = """
      MapSet.new(list)
      """

      assert check(code) == []
    end

    test "does not flag MapSet.new/2" do
      code = """
      MapSet.new(list, fn x -> x * 2 end)
      """

      assert check(code) == []
    end

    test "does not flag Enum.into with empty map literal" do
      code = """
      Enum.into(list, %{})
      """

      assert check(code) == []
    end

    test "does not flag Enum.into with a list" do
      code = """
      Enum.into(map, [], fn {k, v} -> {k, v} end)
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces Enum.into(enum, MapSet.new()) with MapSet.new(enum)" do
      code = """
      Enum.into(list, MapSet.new())
      """

      result = fix(code)
      assert result =~ "MapSet.new(list)"
      refute result =~ "Enum.into"
    end

    test "replaces Enum.into(enum, MapSet.new(), fun) with MapSet.new(enum, fun)" do
      code = """
      Enum.into(list, MapSet.new(), fn x -> x * 2 end)
      """

      result = fix(code)
      assert result =~ "MapSet.new"
      assert result =~ "fn x -> x * 2 end"
      refute result =~ "Enum.into"
    end

    test "replaces piped Enum.into(MapSet.new()) with MapSet.new(enum)" do
      code = """
      pairs |> Enum.into(MapSet.new())
      """

      result = fix(code)
      assert result =~ "MapSet.new(pairs)"
      refute result =~ "Enum.into"
    end

    test "replaces piped Enum.into(MapSet.new(), fun) with piped MapSet.new(fun)" do
      code = """
      list |> Enum.into(MapSet.new(), fn x -> x * 2 end)
      """

      result = fix(code)
      assert result =~ "|> MapSet.new("
      refute result =~ "Enum.into"
    end

    test "replaces Enum.into in a longer pipeline" do
      code = """
      routes
      |> Stream.with_index()
      |> Enum.into(MapSet.new(), fn {r, i} -> {i, r} end)
      """

      result = fix(code)
      assert result =~ "|> MapSet.new("
      assert result =~ "Stream.with_index"
      refute result =~ "Enum.into"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def build(data) do
          set = Enum.into(data, MapSet.new())
          MapSet.size(set)
        end
      end
      """

      result = fix(code)
      assert result =~ "MapSet.new"
      assert result =~ "MapSet.size(set)"
      refute result =~ "Enum.into"
    end
  end

  describe "fix round-trip" do
    test "fixed 2-arg produces no issues" do
      code = """
      Enum.into(list, MapSet.new())
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoEnumIntoEmptyMapset.check(ast, []) == []
    end

    test "fixed 3-arg produces no issues" do
      code = """
      Enum.into(list, MapSet.new(), fn x -> x * 2 end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoEnumIntoEmptyMapset.check(ast, []) == []
    end

    test "fixed piped produces no issues" do
      code = """
      routes
      |> Stream.with_index()
      |> Enum.into(MapSet.new(), fn {r, i} -> {i, r} end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoEnumIntoEmptyMapset.check(ast, []) == []
    end
  end
end
