defmodule Credence.Rule.NoMapKeysOrValuesForIterationTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoMapKeysOrValuesForIteration.check(ast, [])
  end

  describe "NoMapKeysOrValuesForIteration" do
    test "passes iterating map directly" do
      code = """
      defmodule Good do
        def all_zero?(map) do
          Enum.all?(map, fn {_k, v} -> v == 0 end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Map.values used without Enum" do
      code = """
      defmodule Safe do
        def get_values(map), do: Map.values(map)
      end
      """

      assert check(code) == []
    end

    test "detects Enum.all?(Map.values(m), ...)" do
      code = """
      defmodule Bad do
        def all_zero?(degrees) do
          Enum.all?(Map.values(degrees), fn v -> v == 0 end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_map_keys_or_values_for_iteration

      assert issue.message =~ "Map.values"
      assert issue.message =~ "Enum.all?"
      assert issue.meta.line != nil
    end

    test "detects Map.values(m) |> Enum.max()" do
      code = """
      defmodule Bad do
        def max_value(map) do
          Map.values(map) |> Enum.max()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).message =~ "Map.values"
    end

    test "detects Map.keys(m) |> Enum.map(...)" do
      code = """
      defmodule Bad do
        def key_strings(map) do
          Map.keys(map) |> Enum.map(&to_string/1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).message =~ "Map.keys"
    end

    test "detects triple-pipe: map |> Map.values() |> Enum.max()" do
      code = """
      defmodule Bad do
        def max_val(map) do
          map |> Map.values() |> Enum.max()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "passes Map.keys used in non-Enum context" do
      code = """
      defmodule Safe do
        def key_count(map), do: length(Map.keys(map))
      end
      """

      assert check(code) == []
    end
  end
end
