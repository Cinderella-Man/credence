defmodule Credence.Syntax.FixDoEqualsKeywordSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixDoEqualsKeywordSyntax

  defp analyze(code), do: FixDoEqualsKeywordSyntax.analyze(code)
  defp fix(code), do: FixDoEqualsKeywordSyntax.fix(code)

  test "fixes do = to do: in a function definition" do
    input = """
    defmodule M do
      def f(x), do = x + 1
    end
    """

    expected = """
    defmodule M do
      def f(x), do: x + 1
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes do = expr do ... end to block form in for comprehension" do
    input = """
    defmodule FixDoEquals do
      def build(list) do
        for x <- list, do = x + 1 do
          result
        end
      end
    end
    """

    expected = """
    defmodule FixDoEquals do
      def build(list) do
        for x <- list do
          x + 1
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("""
           defmodule M do
             def f(x), do = x + 1
           end
           """)) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("""
           defmodule M do
             def f(x), do = x + 1
           end
           """))
  end
end
