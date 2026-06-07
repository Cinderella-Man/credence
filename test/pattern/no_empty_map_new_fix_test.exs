defmodule Credence.Pattern.NoEmptyMapNewFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEmptyMapNew

  test "replaces Map.new() with %{}" do
    code = """
    memo = Map.new()
    """

    expected = """
    memo = %{}
    """

    assert fix(NoEmptyMapNew, code) == expected
  end

  test "replaces Map.new() in a function argument" do
    code = """
    solve(coins, amount, Map.new())
    """

    expected = """
    solve(coins, amount, %{})
    """

    assert fix(NoEmptyMapNew, code) == expected
  end

  test "replaces Map.new without parentheses" do
    code = """
    memo = Map.new
    """

    expected = """
    memo = %{}
    """

    assert fix(NoEmptyMapNew, code) == expected
  end

  test "replaces standalone Map.new() on the left of a pipe" do
    code = """
    Map.new() |> foo()
    """

    expected = """
    %{} |> foo()
    """

    assert fix(NoEmptyMapNew, code) == expected
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

    assert fix(NoEmptyMapNew, code) == expected
  end

  describe "no-op" do
    test "leaves piped Map.new() alone" do
      code = """
      list |> Map.new()
      """

      assert fix(NoEmptyMapNew, code) == code
    end

    test "leaves Map.new(enum) alone" do
      code = """
      Map.new(pairs)
      """

      assert fix(NoEmptyMapNew, code) == code
    end

    test "leaves the %{} literal alone" do
      code = """
      memo = %{}
      """

      assert fix(NoEmptyMapNew, code) == code
    end
  end

  describe "fix round-trip produces no issues" do
    test "single assignment" do
      fixed = fix(NoEmptyMapNew, "memo = Map.new()\n")
      ast = Sourceror.parse_string!(fixed)
      assert NoEmptyMapNew.check(ast, []) == []
    end

    test "function argument" do
      fixed = fix(NoEmptyMapNew, "solve(coins, amount, Map.new())\n")
      ast = Sourceror.parse_string!(fixed)
      assert NoEmptyMapNew.check(ast, []) == []
    end
  end
end
