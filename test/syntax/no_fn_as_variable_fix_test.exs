defmodule Credence.Syntax.NoFnAsVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoFnAsVariable

  defp analyze(code), do: NoFnAsVariable.analyze(code)
  defp fix(code), do: NoFnAsVariable.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Fix do
      def foo([fn | rest]) do
        fn
      end
    end
    """

    expected = """
    defmodule Fix do
      def foo([func | rest]) do
        func
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule Fix do
      def foo([fn | rest]) do
        fn
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Fix do
      def foo([fn | rest]) do
        fn
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
