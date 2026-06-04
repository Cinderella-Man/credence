defmodule Credence.Pattern.NoEmptyMapNewCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEmptyMapNew

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEmptyMapNew.check(ast, [])
  end

  describe "flags zero-argument Map.new()" do
    test "detects Map.new() with no arguments" do
      code = """
      memo = Map.new()
      """

      [issue] = check(code)
      assert issue.rule == :no_empty_map_new
      assert issue.message =~ "%{}"
    end

    test "detects Map.new() in a function call argument" do
      code = """
      solve(coins, amount, Map.new())
      """

      [issue] = check(code)
      assert issue.rule == :no_empty_map_new
    end

    test "detects Map.new without parentheses" do
      code = """
      memo = Map.new
      """

      [issue] = check(code)
      assert issue.rule == :no_empty_map_new
    end

    test "detects Map.new() on the left of a pipe (it is standalone)" do
      code = """
      Map.new() |> foo()
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
  end

  describe "no issue" do
    test "does not flag Map.new(enum, fun)" do
      code = """
      Map.new(list, fn x -> {x, true} end)
      """

      assert check(code) == []
    end

    test "does not flag Map.new(enum)" do
      code = """
      Map.new(pairs)
      """

      assert check(code) == []
    end

    test "does not flag piped Map.new() (the pipe supplies an argument)" do
      code = """
      list |> Map.new()
      """

      assert check(code) == []
    end

    test "does not flag a chained pipe into Map.new()" do
      code = """
      a |> b |> Map.new()
      """

      assert check(code) == []
    end

    test "does not flag the %{} literal" do
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
end
