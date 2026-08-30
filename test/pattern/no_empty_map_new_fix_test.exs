defmodule Credence.Pattern.NoEmptyMapNewFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEmptyMapNew

  test "replaces Map.new() with %{}" do
    code = "memo = Map.new()"

    expected = "memo = %{}"

    confirm_fix(fix(NoEmptyMapNew, code), expected)
  end

  test "replaces Map.new() in a function argument" do
    code = "solve(coins, amount, Map.new())"

    expected = "solve(coins, amount, %{})"

    confirm_fix(fix(NoEmptyMapNew, code), expected)
  end

  test "replaces Map.new without parentheses" do
    code = "memo = Map.new"

    expected = "memo = %{}"

    confirm_fix(fix(NoEmptyMapNew, code), expected)
  end

  test "replaces standalone Map.new() on the left of a pipe" do
    code = "Map.new() |> foo()"

    expected = "%{} |> foo()"

    confirm_fix(fix(NoEmptyMapNew, code), expected)
  end

  test "replaces standalone Map.new() nested in a pipe RHS argument" do
    code = "items |> process(Map.new())"

    expected = "items |> process(%{})"

    confirm_fix(fix(NoEmptyMapNew, code), expected)
  end

  test "replaces every occurrence and preserves surrounding code" do
    code = """
    defmodule M do
      def build do
        memo = Map.new()
        Map.keys(memo)
      end
    end
    """

    expected = """
    defmodule M do
      def build do
        memo = %{}
        Map.keys(memo)
      end
    end
    """

    confirm_fix(fix(NoEmptyMapNew, code), expected)
  end

  describe "no-op" do
    test "leaves piped Map.new() alone" do
      code = "list |> Map.new()"

      confirm_fix(fix(NoEmptyMapNew, code), code)
    end

    test "leaves Map.new(enum) alone" do
      code = "Map.new(pairs)"

      confirm_fix(fix(NoEmptyMapNew, code), code)
    end

    test "leaves the %{} literal alone" do
      code = "memo = %{}"

      confirm_fix(fix(NoEmptyMapNew, code), code)
    end

    test "leaves Map.new() through a lexical Map alias alone" do
      code = """
      alias MyMap, as: Map
      Map.new()
      """

      confirm_fix(fix(NoEmptyMapNew, code), code)
    end

    test "leaves Map.new() inside quoted code alone" do
      code = "quote do: Map.new()"

      confirm_fix(fix(NoEmptyMapNew, code), code)
    end
  end

  describe "fix round-trip produces no issues" do
    test "single assignment" do
      fixed =
        fix(NoEmptyMapNew, "memo = Map.new()")

      assert clean?(NoEmptyMapNew, fixed)
    end

    test "function argument" do
      fixed =
        fix(NoEmptyMapNew, "solve(coins, amount, Map.new())")

      assert clean?(NoEmptyMapNew, fixed)
    end
  end
end
