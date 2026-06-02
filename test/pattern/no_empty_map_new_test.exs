defmodule Credence.Pattern.NoEmptyMapNewTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEmptyMapNew

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEmptyMapNew.check(ast, [])
  end

  defp fix(code), do: Credence.RuleHelpers.apply_rule_fix(NoEmptyMapNew, code, [])

  describe "check" do
    test "detects Map.new() with no arguments" do
      code = """
      memo = Map.new()
      """

      [issue] = check(code)
      assert issue.rule == :no_empty_map_new
      assert issue.message =~ "%{}"
    end

    test "detects Map.new() in a function call" do
      code = """
      solve(coins, amount, Map.new())
      """

      [issue] = check(code)
      assert issue.rule == :no_empty_map_new
    end

    test "detects multiple occurrences" do
      code = """
      defmodule Bad do
        def build do
          a = Map.new()
          b = Map.new()
          {a, b}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :no_empty_map_new))
    end

    # ── Negative cases ──────────────────────────────────────────

    test "does not flag Map.new(enum)" do
      code = """
      Map.new(list, fn x -> {x, true} end)
      """

      assert check(code) == []
    end

    test "does not flag Map.new(pairs)" do
      code = """
      Map.new(pairs)
      """

      assert check(code) == []
    end

    test "does not flag piped Map.new()" do
      code = """
      list |> Map.new()
      """

      assert check(code) == []
    end

    test "does not flag %{} literal" do
      code = """
      memo = %{}
      """

      assert check(code) == []
    end

    test "does not flag Map.put" do
      code = """
      Map.put(map, :key, value)
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces Map.new() with %{}" do
      code = """
      memo = Map.new()
      """

      result = fix(code)
      assert result =~ "%{}"
      refute result =~ "Map.new()"
    end

    test "replaces Map.new() in function argument" do
      code = """
      solve(coins, amount, Map.new())
      """

      result = fix(code)
      assert result =~ "%{}"
      refute result =~ "Map.new()"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def build do
          memo = Map.new()
          Map.keys(memo)
        end
      end
      """

      result = fix(code)
      assert result =~ "%{}"
      assert result =~ "Map.keys(memo)"
      refute result =~ "Map.new()"
    end
  end

  describe "fix round-trip" do
    test "fixed code produces no issues" do
      code = """
      memo = Map.new()
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoEmptyMapNew.check(ast, []) == []
    end

    test "fixed function arg produces no issues" do
      code = """
      solve(coins, amount, Map.new())
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoEmptyMapNew.check(ast, []) == []
    end
  end
end
