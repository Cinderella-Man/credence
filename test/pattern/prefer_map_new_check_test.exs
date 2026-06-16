defmodule Credence.Pattern.PreferMapNewCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapNew

  describe "flags" do
    test "Enum.into(enum, %{})" do
      code = "Enum.into(list, %{})"

      [issue] = check(PreferMapNew, code)
      assert issue.rule == :prefer_map_new
      assert issue.message =~ "Map.new"
    end

    test "piped Enum.into(%{})" do
      code = "list |> Enum.into(%{})"

      [issue] = check(PreferMapNew, code)
      assert issue.rule == :prefer_map_new
    end

    test "Enum.into in a longer pipeline" do
      code = """
      keys
      |> Enum.zip(vals)
      |> Enum.into(%{})
      """

      [issue] = check(PreferMapNew, code)
      assert issue.rule == :prefer_map_new
    end

    test "multiple occurrences" do
      code = """
      defmodule Bad do
        def build(a, b, c, d) do
          m1 = Enum.into(a, %{})
          m2 = b |> Enum.into(%{})
          {m1, m2}
        end
      end
      """

      issues = check(PreferMapNew, code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :prefer_map_new))
    end
  end

  describe "does not flag" do
    test "Map.new(enum)" do
      code = "Map.new(list)"

      assert clean?(PreferMapNew, code)
    end

    test "Enum.into with a variable target" do
      code = "Enum.into(list, existing_map)"

      assert clean?(PreferMapNew, code)
    end

    test "Enum.into with a non-empty map literal" do
      code = "Enum.into(list, %{a: 1})"

      assert clean?(PreferMapNew, code)
    end

    test "Enum.into(enum, map, fun)" do
      code = "Enum.into(list, %{}, fn x -> {x, x} end)"

      assert clean?(PreferMapNew, code)
    end

    test "Enum.into with a list target" do
      code = "Enum.into(map, [])"

      assert clean?(PreferMapNew, code)
    end

    test "Map.put" do
      code = "Map.put(map, :key, value)"

      assert clean?(PreferMapNew, code)
    end
  end
end
