defmodule Credence.Pattern.NoEnumIntoEmptyMapTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumIntoEmptyMap

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEnumIntoEmptyMap.check(ast, [])
  end

  defp fix(code), do: Credence.RuleHelpers.apply_rule_fix(NoEnumIntoEmptyMap, code, [])

  describe "check" do
    test "detects Enum.into(enum, %{}, fun)" do
      code = """
      Enum.into(list, %{}, fn x -> {x, true} end)
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_map
      assert issue.message =~ "Map.new"
    end

    test "detects Enum.into(enum, %{})" do
      code = """
      Enum.into(pairs, %{})
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_map
      assert issue.message =~ "Map.new"
    end

    test "detects piped Enum.into(%{}, fun)" do
      code = """
      list |> Enum.into(%{}, fn x -> {x, x * 2} end)
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_map
    end

    test "detects piped Enum.into(%{})" do
      code = """
      pairs |> Enum.into(%{})
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_map
    end

    test "detects Enum.into in a longer pipeline" do
      code = """
      routes
      |> Stream.with_index()
      |> Enum.into(%{}, fn {r, i} -> {i, r} end)
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_into_empty_map
    end

    test "detects multiple occurrences" do
      code = """
      defmodule Bad do
        def build(data) do
          a = Enum.into(data, %{}, fn x -> {x, true} end)
          b = Enum.into(other, %{})
          {a, b}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :no_enum_into_empty_map))
    end

    # ── Negative cases ──────────────────────────────────────────

    test "does not flag Enum.into with non-empty map" do
      code = """
      Enum.into(list, %{existing: :value}, fn x -> {x, true} end)
      """

      assert check(code) == []
    end

    test "does not flag Enum.into with a variable map" do
      code = """
      Enum.into(list, existing_map, fn x -> {x, true} end)
      """

      assert check(code) == []
    end

    test "does not flag Map.new" do
      code = """
      Map.new(list, fn x -> {x, true} end)
      """

      assert check(code) == []
    end

    test "does not flag Enum.into with a MapSet" do
      code = """
      Enum.into(list, MapSet.new())
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
    test "replaces Enum.into(enum, %{}, fun) with Map.new(enum, fun)" do
      code = """
      Enum.into(list, %{}, fn x -> {x, x * 2} end)
      """

      result = fix(code)
      assert result =~ "Map.new"
      assert result =~ "fn x -> {x, x * 2} end"
      refute result =~ "Enum.into"
    end

    test "replaces Enum.into(enum, %{}) with Map.new(enum)" do
      code = """
      Enum.into(pairs, %{})
      """

      result = fix(code)
      assert result =~ "Map.new(pairs)"
      refute result =~ "Enum.into"
    end

    test "replaces piped Enum.into(%{}, fun) with piped Map.new(fun)" do
      code = """
      list |> Enum.into(%{}, fn x -> {x, true} end)
      """

      result = fix(code)
      assert result =~ "|> Map.new("
      refute result =~ "Enum.into"
    end

    test "replaces piped Enum.into(%{}) with Map.new(enum)" do
      code = """
      pairs |> Enum.into(%{})
      """

      result = fix(code)
      assert result =~ "Map.new(pairs)"
      refute result =~ "|>"
      refute result =~ "Enum.into"
    end

    test "replaces Enum.into in a longer pipeline" do
      code = """
      routes
      |> Stream.with_index()
      |> Enum.into(%{}, fn {r, i} -> {i, r} end)
      """

      result = fix(code)
      assert result =~ "|> Map.new("
      assert result =~ "Stream.with_index"
      refute result =~ "Enum.into"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def build(data) do
          map = Enum.into(data, %{}, fn x -> {x, true} end)
          Map.keys(map)
        end
      end
      """

      result = fix(code)
      assert result =~ "Map.new"
      assert result =~ "Map.keys(map)"
      refute result =~ "Enum.into"
    end
  end

  describe "fix round-trip" do
    test "fixed 3-arg produces no issues" do
      code = """
      Enum.into(list, %{}, fn x -> {x, true} end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoEnumIntoEmptyMap.check(ast, []) == []
    end

    test "fixed 2-arg produces no issues" do
      code = """
      Enum.into(pairs, %{})
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoEnumIntoEmptyMap.check(ast, []) == []
    end

    test "fixed piped produces no issues" do
      code = """
      routes
      |> Stream.with_index()
      |> Enum.into(%{}, fn {r, i} -> {i, r} end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoEnumIntoEmptyMap.check(ast, []) == []
    end
  end
end
