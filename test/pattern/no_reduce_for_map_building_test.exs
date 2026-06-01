defmodule Credence.Pattern.NoReduceForMapBuildingTest do
  use ExUnit.Case

  alias Credence.Pattern.NoReduceForMapBuilding

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoReduceForMapBuilding.check(ast, [])
  end

  defp fix(code), do: Credence.RuleHelpers.apply_rule_fix(NoReduceForMapBuilding, code, [])

  describe "check — positive cases" do
    test "detects Enum.reduce building a map with Map.put" do
      code = """
      defmodule Bad do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, String.length(x))
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_reduce_for_map_building
      assert issue.message =~ "Map.new/2"
    end

    test "detects piped form" do
      code = """
      defmodule Bad do
        def build(list) do
          list
          |> Enum.reduce(%{}, fn x, acc ->
            Map.put(acc, x, x * 2)
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_reduce_for_map_building
    end

    test "detects single-expression block wrapper" do
      code = """
      defmodule Bad do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, String.length(x))
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_reduce_for_map_building
    end
  end

  describe "check — negative cases" do
    test "does not flag Enum.reduce with non-empty initial map" do
      code = """
      defmodule Good do
        def build(list, existing) do
          Enum.reduce(list, existing, fn x, acc ->
            Map.put(acc, x, String.length(x))
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when value references acc" do
      code = """
      defmodule Good do
        def count_chars(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, Map.get(acc, :default, 0) + 1)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when body has multiple statements" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            key = String.to_atom(x)
            Map.put(acc, key, String.length(x))
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce with sum accumulation" do
      code = """
      defmodule Good do
        def sum(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.new (already idiomatic)" do
      code = """
      defmodule Good do
        def build(list) do
          Map.new(list, fn x -> {x, String.length(x)} end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.into" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.into(list, %{}, fn x -> {x, String.length(x)} end)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix — direct form" do
    test "replaces Enum.reduce with Map.new" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        Map.put(acc, x, String.length(x))
      end)
      """

      result = fix(code)
      assert result =~ "Map.new"
      assert result =~ "fn x ->"
      assert result =~ "String.length(x)"
      refute result =~ "Enum.reduce"
      refute result =~ "Map.put"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def build(list) do
          result = Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, x * 2)
          end)

          Map.size(result)
        end
      end
      """

      result = fix(code)
      assert result =~ "Map.new"
      assert result =~ "Map.size(result)"
      refute result =~ "Enum.reduce"
    end
  end

  describe "fix — piped form" do
    test "replaces piped Enum.reduce with Map.new" do
      code = """
      list
      |> Enum.reduce(%{}, fn x, acc ->
        Map.put(acc, x, x * 2)
      end)
      """

      result = fix(code)
      assert result =~ "|> Map.new"
      assert result =~ "fn x ->"
      refute result =~ "Enum.reduce"
    end

    test "preserves pipeline head and tail" do
      code = """
      list
      |> Enum.filter(&valid?/1)
      |> Enum.reduce(%{}, fn x, acc ->
        Map.put(acc, x, transform(x))
      end)
      |> Map.keys()
      """

      result = fix(code)
      assert result =~ "|> Enum.filter"
      assert result =~ "|> Map.new"
      assert result =~ "|> Map.keys()"
      refute result =~ "Enum.reduce"
    end
  end

  describe "fix round-trip" do
    test "fixed direct form produces no issues" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        Map.put(acc, x, String.length(x))
      end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoReduceForMapBuilding.check(ast, []) == []
    end

    test "fixed piped form produces no issues" do
      code = """
      list
      |> Enum.reduce(%{}, fn x, acc ->
        Map.put(acc, x, x * 2)
      end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoReduceForMapBuilding.check(ast, []) == []
    end
  end
end
