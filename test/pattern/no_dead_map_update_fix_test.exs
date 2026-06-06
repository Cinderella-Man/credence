defmodule Credence.Pattern.NoDeadMapUpdateFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoDeadMapUpdate

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoDeadMapUpdate, code, [])

  describe "fix — removes the dead identity update" do
    test "piped Map.update |> Map.drop" do
      code = """
      map |> Map.update(prev, 0, & &1) |> Map.drop([prev])
      """

      expected = """
      Map.drop(map, [prev])
      """

      assert fix(code) == expected
    end

    test "piped Map.update |> Map.delete" do
      code = """
      map |> Map.update(key, 0, & &1) |> Map.delete(key)
      """

      expected = """
      Map.delete(map, key)
      """

      assert fix(code) == expected
    end

    test "direct Map.drop(Map.update(...), [key])" do
      code = """
      Map.drop(Map.update(map, key, 0, & &1), [key])
      """

      expected = """
      Map.drop(map, [key])
      """

      assert fix(code) == expected
    end

    test "direct Map.delete(Map.update(...), key)" do
      code = """
      Map.delete(Map.update(map, key, 0, & &1), key)
      """

      expected = """
      Map.delete(map, key)
      """

      assert fix(code) == expected
    end

    test "preserves other keys in the drop list" do
      code = """
      map |> Map.update(key, 0, & &1) |> Map.drop([key, other])
      """

      expected = """
      Map.drop(map, [key, other])
      """

      assert fix(code) == expected
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def clean(map, key) do
          result =
            map
            |> Map.update(key, 0, & &1)
            |> Map.drop([key])

          {:ok, result}
        end
      end
      """

      expected = """
      defmodule M do
        def clean(map, key) do
          result =
            Map.drop(map, [key])

          {:ok, result}
        end
      end
      """

      assert fix(code) == expected
    end

    test "fixed code produces no further issues (round-trip)" do
      code = """
      map |> Map.update(prev, 0, & &1) |> Map.drop([prev])
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoDeadMapUpdate.check(ast, []) == []
    end
  end

  describe "no-op — unsafe or non-matching shapes are untouched" do
    test "arithmetic fun is not rewritten" do
      code = """
      map |> Map.update(prev, 0, &(&1 - count)) |> Map.drop([prev])
      """

      assert fix(code) == code
    end

    test "non-literal default is not rewritten" do
      code = """
      map |> Map.update(key, default(), & &1) |> Map.drop([key])
      """

      assert fix(code) == code
    end

    test "differing key is not rewritten" do
      code = """
      map |> Map.update(key_a, 0, & &1) |> Map.drop([key_b])
      """

      assert fix(code) == code
    end

    test "lone Map.update is not rewritten" do
      code = """
      map |> Map.update(key, 0, & &1)
      """

      assert fix(code) == code
    end
  end
end
