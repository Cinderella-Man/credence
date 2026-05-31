defmodule Credence.Pattern.NoMapKeysOrValuesForIterationCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoMapKeysOrValuesForIteration

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoMapKeysOrValuesForIteration.check(ast, [])
  end

  describe "flags nested form" do
    test "Enum.all?(Map.values(m), ...)" do
      assert [%Issue{rule: :no_map_keys_or_values_for_iteration}] =
               check("Enum.all?(Map.values(degrees), fn v -> v == 0 end)")
    end

    test "Enum.sum(Map.values(m))" do
      assert [%Issue{rule: :no_map_keys_or_values_for_iteration}] =
               check("Enum.sum(Map.values(m))")
    end

    test "Enum.filter(Map.values(m), ...)" do
      assert [%Issue{rule: :no_map_keys_or_values_for_iteration}] =
               check("Enum.filter(Map.values(m), fn v -> v > 0 end)")
    end

    test "Enum.count(Map.values(m))" do
      assert [%Issue{rule: :no_map_keys_or_values_for_iteration}] =
               check("Enum.count(Map.values(m))")
    end

    test "multiple violations in same module" do
      code = """
      defmodule Example do
        def f(m), do: Enum.all?(Map.values(m), fn v -> v == 0 end)
        def g(m), do: Enum.count(Map.keys(m))
      end
      """

      assert length(check(code)) == 2
    end
  end

  describe "flags pipe form" do
    test "Map.keys(m) |> Enum.map(&to_string/1)" do
      assert [%Issue{rule: :no_map_keys_or_values_for_iteration}] =
               check("Map.keys(map) |> Enum.map(&to_string/1)")
    end
  end

  describe "flags triple-pipe form" do
    test "map |> Map.values() |> Enum.count()" do
      assert [%Issue{rule: :no_map_keys_or_values_for_iteration}] =
               check("map |> Map.values() |> Enum.count()")
    end
  end

  describe "does NOT flag" do
    test "iterating map directly" do
      assert check("Enum.all?(m, fn {_, v} -> v == 0 end)") == []
    end

    test "Map.values used without Enum" do
      assert check("Map.values(m)") == []
    end

    test "Map.keys in non-Enum context" do
      assert check("length(Map.keys(m))") == []
    end

    test "unfixable Enum function" do
      assert check("Enum.chunk_every(Map.values(m), 2)") == []
    end

    test "Map.values |> Enum.max — already idiomatic" do
      assert check("Map.values(map) |> Enum.max()") == []
    end

    test "Map.values |> Enum.min — already idiomatic" do
      assert check("Map.values(map) |> Enum.min()") == []
    end

    test "Enum.max(Map.values(m)) — already idiomatic" do
      assert check("Enum.max(Map.values(m))") == []
    end

    test "Map.keys |> Enum.max — already idiomatic" do
      assert check("Map.keys(map) |> Enum.max()") == []
    end
  end

  describe "metadata" do
    test "meta.line is set" do
      [issue] = check("Enum.all?(Map.values(m), fn v -> v == 0 end)")
      assert issue.meta.line != nil
    end

    test "message references both Map and Enum functions" do
      [issue] = check("Enum.all?(Map.values(m), fn v -> v == 0 end)")
      assert issue.message =~ "Map.values"
      assert issue.message =~ "Enum.all?"
    end
  end
end
