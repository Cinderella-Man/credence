defmodule Credence.Pattern.NoDeadMapUpdateCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoDeadMapUpdate

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoDeadMapUpdate.check(ast, [])
  end

  describe "fires — identity fun (& &1) + literal default, key dropped" do
    test "piped Map.update |> Map.drop on same key" do
      code = """
      map |> Map.update(prev, 0, & &1) |> Map.drop([prev])
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_dead_map_update
    end

    test "piped Map.update |> Map.delete on same key" do
      code = """
      map |> Map.update(key, 0, & &1) |> Map.delete(key)
      """

      assert length(check(code)) == 1
    end

    test "direct Map.drop(Map.update(...), [key])" do
      code = """
      Map.drop(Map.update(map, key, 0, & &1), [key])
      """

      assert length(check(code)) == 1
    end

    test "direct Map.delete(Map.update(...), key)" do
      code = """
      Map.delete(Map.update(map, key, 0, & &1), key)
      """

      assert length(check(code)) == 1
    end

    test "fires for each non-numeric literal default" do
      for default <- ["0", "nil", ":none", "\"\"", "[]", "-1"] do
        code = "map |> Map.update(key, #{default}, & &1) |> Map.drop([key])\n"
        assert length(check(code)) == 1, "expected fire for default #{default}"
      end
    end

    test "detects multiple instances" do
      code = """
      defmodule M do
        def clean(m, a, b) do
          m
          |> Map.update(a, 0, & &1)
          |> Map.drop([a])
          |> Map.update(b, 0, & &1)
          |> Map.drop([b])
        end
      end
      """

      assert length(check(code)) == 2
    end
  end

  describe "no issue — non-identity fun (would drop a raise/side effect)" do
    test "arithmetic fun is left alone" do
      code = """
      map |> Map.update(prev, 0, &(&1 - count)) |> Map.drop([prev])
      """

      assert check(code) == []
    end

    test "increment fun is left alone" do
      code = """
      map |> Map.update(key, 0, &(&1 + 1)) |> Map.delete(key)
      """

      assert check(code) == []
    end

    test "named-capture fun is left alone" do
      code = """
      map |> Map.update(key, 0, &to_string/1) |> Map.drop([key])
      """

      assert check(code) == []
    end

    test "fn-form identity is left alone (only & &1 capture is recognized)" do
      code = """
      map |> Map.update(key, 0, fn x -> x end) |> Map.drop([key])
      """

      assert check(code) == []
    end

    test "direct form with arithmetic fun is left alone" do
      code = """
      Map.delete(Map.update(map, key, 0, &(&1 - count)), key)
      """

      assert check(code) == []
    end
  end

  describe "no issue — non-literal default (would drop its eager evaluation)" do
    test "function-call default is left alone" do
      code = """
      map |> Map.update(key, default(), & &1) |> Map.drop([key])
      """

      assert check(code) == []
    end

    test "variable default is left alone" do
      code = """
      map |> Map.update(key, seed, & &1) |> Map.drop([key])
      """

      assert check(code) == []
    end
  end

  describe "no issue — not a dead update at all" do
    test "drop key differs from update key" do
      code = """
      map |> Map.update(key_a, 0, & &1) |> Map.drop([key_b])
      """

      assert check(code) == []
    end

    test "delete key differs from update key" do
      code = """
      map |> Map.update(key_a, 0, & &1) |> Map.delete(key_b)
      """

      assert check(code) == []
    end

    test "Map.update without subsequent drop/delete" do
      code = """
      map |> Map.update(key, 0, & &1)
      """

      assert check(code) == []
    end

    test "Map.drop without preceding Map.update" do
      code = """
      Map.drop(map, [key])
      """

      assert check(code) == []
    end

    test "drop list does not contain update key" do
      code = """
      map |> Map.update(key, 0, & &1) |> Map.drop([other_key])
      """

      assert check(code) == []
    end
  end
end
