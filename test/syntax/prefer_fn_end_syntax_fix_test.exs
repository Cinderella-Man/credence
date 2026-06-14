defmodule Credence.Syntax.PreferFnEndSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferFnEndSyntax

  defp analyze(code), do: PreferFnEndSyntax.analyze(code)
  defp fix(code), do: PreferFnEndSyntax.fix(code)

  describe "fixes bare arrow syntax" do
    test "single parameter in function call" do
      input = "Enum.reduce(1..n, 1, acc -> acc * n)"

      expected = "Enum.reduce(1..n, 1, fn acc -> acc * n end)"

      confirm_fix(fix(input), expected)
    end

    test "multi-parameter in function call" do
      input = "Enum.reduce(list, 0, x, acc -> x + acc)"

      expected = "Enum.reduce(list, 0, fn x, acc -> x + acc end)"

      confirm_fix(fix(input), expected)
    end

    test "bare arrow in assignment" do
      input = "f = x -> x + 1"

      expected = "f = fn x -> x + 1 end"

      confirm_fix(fix(input), expected)
    end
  end

  describe "does not change valid code" do
    test "fn ... end syntax unchanged" do
      code = "Enum.reduce(1..n, 1, fn acc, _i -> acc * n end)"

      confirm_fix(fix(code), code)
    end

    test "case expression unchanged" do
      code = """
      case x do
        y -> y
      end
      """

      confirm_fix(fix(code), code)
    end

    test "cond expression unchanged" do
      code = """
      defmodule Solution do
        def check(value) do
          cond do
            value > 3 -> :big
            true -> :small
          end
        end
      end
      """

      confirm_fix(fix(code), code)
    end
  end

  test "fixed output no longer flags" do
    assert analyze(fix("Enum.reduce(1..n, 1, acc -> acc * n)")) == []
  end

  test "fixed output is well-formed (parses)" do
    # the repaired source must be valid Elixir
    assert valid_syntax?(fix("Enum.reduce(1..n, 1, acc -> acc * n)"))
  end
end
