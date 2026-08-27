defmodule Credence.Pattern.NoEmptyMapNewCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEmptyMapNew

  describe "flags zero-argument Map.new()" do
    test "detects Map.new() with no arguments" do
      code = "memo = Map.new()"

      [issue] = check(NoEmptyMapNew, code)
      assert issue.rule == :no_empty_map_new
      assert issue.message =~ "%{}"
    end

    test "detects Map.new() in a function call argument" do
      code = "solve(coins, amount, Map.new())"

      [issue] = check(NoEmptyMapNew, code)
      assert issue.rule == :no_empty_map_new
    end

    test "detects Map.new without parentheses" do
      code = "memo = Map.new"

      [issue] = check(NoEmptyMapNew, code)
      assert issue.rule == :no_empty_map_new
    end

    test "detects Map.new() on the left of a pipe (it is standalone)" do
      code = "Map.new() |> foo()"

      [issue] = check(NoEmptyMapNew, code)
      assert issue.rule == :no_empty_map_new
    end

    test "detects a standalone Map.new() nested in a pipe RHS argument" do
      code = "items |> process(Map.new())"

      [issue] = check(NoEmptyMapNew, code)
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

      issues = check(NoEmptyMapNew, code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :no_empty_map_new))
    end
  end

  describe "no issue" do
    test "does not flag Map.new(enum, fun)" do
      code = "Map.new(list, fn x -> {x, true} end)"

      assert check(NoEmptyMapNew, code) == []
    end

    test "does not flag Map.new(enum)" do
      code = "Map.new(pairs)"

      assert check(NoEmptyMapNew, code) == []
    end

    test "does not flag piped Map.new() (the pipe supplies an argument)" do
      code = "list |> Map.new()"

      assert check(NoEmptyMapNew, code) == []
    end

    test "does not flag a chained pipe into Map.new()" do
      code = "a |> b |> Map.new()"

      assert check(NoEmptyMapNew, code) == []
    end

    test "does not flag the %{} literal" do
      code = "memo = %{}"

      assert check(NoEmptyMapNew, code) == []
    end

    test "does not flag Map.put" do
      code = "Map.put(map, :key, value)"

      assert check(NoEmptyMapNew, code) == []
    end

    # `&Map.new/0` is an arity capture whose `Map.new` operand is AST-identical
    # to a real `Map.new()` call. Rewriting it would produce `&%{}/0`, which does
    # not compile, so it must not be flagged.
    test "does not flag the arity capture &Map.new/0" do
      code = "build = &Map.new/0"

      assert check(NoEmptyMapNew, code) == []
    end

    test "does not flag Map.new() when Map is a lexical alias" do
      code = """
      alias MyMap, as: Map
      Map.new()
      """

      assert check(NoEmptyMapNew, code) == []
    end

    test "does not flag Map.new() inside quoted code" do
      code = "quote do: Map.new()"

      assert check(NoEmptyMapNew, code) == []
    end
  end
end
