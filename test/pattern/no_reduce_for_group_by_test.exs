defmodule Credence.Pattern.NoReduceForGroupByTest do
  use ExUnit.Case

  alias Credence.Pattern.NoReduceForGroupBy

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoReduceForGroupBy.check(ast, [])
  end

  defp fix(code), do: Credence.RuleHelpers.apply_rule_fix(NoReduceForGroupBy, code, [])

  describe "check — positive cases" do
    test "detects Enum.reduce with Map.update list prepend (direct form)" do
      code = """
      defmodule Bad do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_reduce_for_group_by
      assert issue.message =~ "Enum.group_by"
    end

    test "detects Enum.reduce with Map.update list prepend (piped form)" do
      code = """
      defmodule Bad do
        def group(list) do
          list
          |> Enum.reduce(%{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_reduce_for_group_by
    end

    test "detects Enum.reduce with binding + Map.update" do
      code = """
      defmodule Bad do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            key = String.first(x)
            Map.update(acc, key, [x], &[x | &1])
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_reduce_for_group_by
    end

    test "detects pipeline with Map.new reverse" do
      code = """
      defmodule Bad do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_reduce_for_group_by
    end
  end

  describe "check — negative cases" do
    test "does not flag Enum.group_by" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.group_by(list, &String.first/1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce with Map.put" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, String.length(x))
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce with non-empty initial map" do
      code = """
      defmodule Good do
        def group(list, existing) do
          Enum.reduce(list, existing, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce with different default value" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), 0, &(&1 + 1))
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce with different update function" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &(&1 ++ [x]))
          end)
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
  end

  describe "fix — pipeline with Map.new reverse" do
    test "replaces reduce |> Map.new(reverse) with Enum.group_by" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        Map.update(acc, String.first(x), [x], &[x | &1])
      end)
      |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
      """

      result = fix(code)
      assert result =~ "Enum.group_by"
      assert result =~ "fn x ->"
      assert result =~ "String.first(x)"
      refute result =~ "Enum.reduce"
      refute result =~ "Map.update"
      refute result =~ "Map.new"
      refute result =~ "Enum.reverse"
    end

    test "replaces reduce with binding |> Map.new(reverse) with Enum.group_by" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        key = String.first(x)
        Map.update(acc, key, [x], &[x | &1])
      end)
      |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
      """

      result = fix(code)
      assert result =~ "Enum.group_by"
      assert result =~ "fn x ->"
      assert result =~ "String.first(x)"
      refute result =~ "Enum.reduce"
      refute result =~ "Map.update"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def group(list) do
          result =
            Enum.reduce(list, %{}, fn x, acc ->
              Map.update(acc, String.first(x), [x], &[x | &1])
            end)
            |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)

          Map.keys(result)
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.group_by"
      assert result =~ "Map.keys(result)"
      refute result =~ "Enum.reduce"
    end
  end

  describe "fix round-trip" do
    test "fixed code produces no issues" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        Map.update(acc, String.first(x), [x], &[x | &1])
      end)
      |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoReduceForGroupBy.check(ast, []) == []
    end

    test "fixed code with binding produces no issues" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        key = String.first(x)
        Map.update(acc, key, [x], &[x | &1])
      end)
      |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoReduceForGroupBy.check(ast, []) == []
    end
  end
end
