defmodule Credence.Syntax.NoFnAsVariableAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoFnAsVariable

  defp analyze(code), do: NoFnAsVariable.analyze(code)

  test "flags the unparseable code" do
    code = """
    defmodule Fix do
      def foo([fn | rest]) do
        fn
      end
    end
    """

    assert [%Issue{rule: :no_fn_as_variable}] = analyze(code)
  end

  test "leaves good code alone" do
    assert analyze("def foo(x), do: x") == []
  end
end
