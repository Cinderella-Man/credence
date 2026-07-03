defmodule Credence.Syntax.PreferDivFunctionOverInfixAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferDivFunctionOverInfix

  defp analyze(code), do: PreferDivFunctionOverInfix.analyze(code)

  test "flags infix div usage" do
    source = "def divide(a, b), do: a div b"

    assert [%Issue{rule: :prefer_div_function_over_infix}] = analyze(source)
  end

  test "flags infix rem usage" do
    source = "def modulo(a, b), do: a rem b"

    assert [%Issue{rule: :prefer_div_function_over_infix}] = analyze(source)
  end

  test "leaves function call syntax alone" do
    source = """
    defmodule Example do
      def divide(a, b), do: div(a, b)
      def modulo(a, b), do: rem(a, b)
    end
    """

    assert analyze(source) == []
  end

  test "leaves comments alone" do
    source = "# a div b"

    assert analyze(source) == []
  end
end
