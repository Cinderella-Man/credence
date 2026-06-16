defmodule Credence.Pattern.NoDeadMapUpdateFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDeadMapUpdate

  describe "fix — removes the dead identity update" do
    test "piped Map.update |> Map.drop" do
      code = "map |> Map.update(prev, 0, & &1) |> Map.drop([prev])"

      expected = "Map.drop(map, [prev])"

      confirm_fix(fix(NoDeadMapUpdate, code), expected)
    end

    test "piped Map.update |> Map.delete" do
      code = "map |> Map.update(key, 0, & &1) |> Map.delete(key)"

      expected = "Map.delete(map, key)"

      confirm_fix(fix(NoDeadMapUpdate, code), expected)
    end

    test "direct Map.drop(Map.update(...), [key])" do
      code = "Map.drop(Map.update(map, key, 0, & &1), [key])"

      expected = "Map.drop(map, [key])"

      confirm_fix(fix(NoDeadMapUpdate, code), expected)
    end

    test "direct Map.delete(Map.update(...), key)" do
      code = "Map.delete(Map.update(map, key, 0, & &1), key)"

      expected = "Map.delete(map, key)"

      confirm_fix(fix(NoDeadMapUpdate, code), expected)
    end

    test "preserves other keys in the drop list" do
      code = "map |> Map.update(key, 0, & &1) |> Map.drop([key, other])"

      expected = "Map.drop(map, [key, other])"

      confirm_fix(fix(NoDeadMapUpdate, code), expected)
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

      confirm_fix(fix(NoDeadMapUpdate, code), expected)
    end

    test "fixed code produces no further issues (round-trip)" do
      code = "map |> Map.update(prev, 0, & &1) |> Map.drop([prev])"

      fixed = fix(NoDeadMapUpdate, code)
      assert clean?(NoDeadMapUpdate, fixed)
    end
  end

  describe "no-op — unsafe or non-matching shapes are untouched" do
    test "arithmetic fun is not rewritten" do
      code = "map |> Map.update(prev, 0, &(&1 - count)) |> Map.drop([prev])"

      confirm_fix(fix(NoDeadMapUpdate, code), code)
    end

    test "non-literal default is not rewritten" do
      code = "map |> Map.update(key, default(), & &1) |> Map.drop([key])"

      confirm_fix(fix(NoDeadMapUpdate, code), code)
    end

    test "differing key is not rewritten" do
      code = "map |> Map.update(key_a, 0, & &1) |> Map.drop([key_b])"

      confirm_fix(fix(NoDeadMapUpdate, code), code)
    end

    test "lone Map.update is not rewritten" do
      code = "map |> Map.update(key, 0, & &1)"

      confirm_fix(fix(NoDeadMapUpdate, code), code)
    end
  end
end
