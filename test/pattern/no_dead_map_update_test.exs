defmodule Credence.Pattern.NoDeadMapUpdateTest do
  use ExUnit.Case

  alias Credence.Pattern.NoDeadMapUpdate

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoDeadMapUpdate.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoDeadMapUpdate, code, [])

  describe "check" do
    test "detects Map.update |> Map.drop on same key (piped)" do
      code = """
      map |> Map.update(prev, 0, &(&1 - count)) |> Map.drop([prev])
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_dead_map_update
    end

    test "detects Map.update |> Map.delete on same key (piped)" do
      code = """
      map |> Map.update(key, 0, &(&1 + 1)) |> Map.delete(key)
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_dead_map_update
    end

    test "detects Map.drop(Map.update(...), [key]) (direct)" do
      code = """
      Map.drop(Map.update(map, key, 0, &(&1 - count)), [key])
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects Map.delete(Map.update(...), key) (direct)" do
      code = """
      Map.delete(Map.update(map, key, 0, &(&1 - count)), key)
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects inside a pipeline with surrounding code" do
      code = """
      defmodule M do
        def clean(map, key, count) do
          map
          |> Map.update(key, 0, &(&1 - count))
          |> Map.drop([key])
          |> Map.update(:other, 0, &(&1 + 1))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does not fire when drop key differs from update key" do
      code = """
      map |> Map.update(key_a, 0, &(&1 - count)) |> Map.drop([key_b])
      """

      assert check(code) == []
    end

    test "does not fire when delete key differs from update key" do
      code = """
      map |> Map.update(key_a, 0, &(&1 - count)) |> Map.delete(key_b)
      """

      assert check(code) == []
    end

    test "does not fire on Map.update without subsequent drop/delete" do
      code = """
      map |> Map.update(key, 0, &(&1 - count))
      """

      assert check(code) == []
    end

    test "does not fire on Map.drop without preceding Map.update" do
      code = """
      Map.drop(map, [key])
      """

      assert check(code) == []
    end

    test "does not fire when drop list does not contain update key" do
      code = """
      map |> Map.update(key, 0, &(&1 - count)) |> Map.drop([other_key])
      """

      assert check(code) == []
    end

    test "detects multiple instances" do
      code = """
      defmodule M do
        def clean(m, a, b) do
          m
          |> Map.update(a, 0, &(&1 - 1))
          |> Map.drop([a])
          |> Map.update(b, 0, &(&1 + 1))
          |> Map.drop([b])
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end
  end

  describe "fix" do
    test "replaces Map.update |> Map.drop with Map.drop" do
      code = """
      map |> Map.update(prev, 0, &(&1 - count)) |> Map.drop([prev])
      """

      result = fix(code)
      assert result =~ "Map.drop"
      refute result =~ "Map.update"
    end

    test "replaces Map.update |> Map.delete with Map.delete" do
      code = """
      map |> Map.update(key, 0, &(&1 + 1)) |> Map.delete(key)
      """

      result = fix(code)
      assert result =~ "Map.delete"
      refute result =~ "Map.update"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      map |> Map.update(prev, 0, &(&1 - count)) |> Map.drop([prev])
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoDeadMapUpdate.check(ast, []) == []
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def clean(map, key, count) do
          result =
            map
            |> Map.update(key, 0, &(&1 - count))
            |> Map.drop([key])

          {:ok, result}
        end
      end
      """

      result = fix(code)
      assert result =~ "{:ok, result}"
      refute result =~ "Map.update"
    end

    test "preserves other keys in drop list" do
      code = """
      map |> Map.update(key, 0, &(&1 - count)) |> Map.drop([key, other])
      """

      result = fix(code)
      assert result =~ "Map.drop"
      assert result =~ "other"
      refute result =~ "Map.update"
    end

    test "does not modify code without dead update" do
      code = """
      map |> Map.update(key, 0, &(&1 - count))
      """

      result = fix(code)
      assert result =~ "Map.update"
    end
  end
end
