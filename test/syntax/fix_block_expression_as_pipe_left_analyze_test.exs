defmodule Credence.Syntax.FixBlockExpressionAsPipeLeftAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixBlockExpressionAsPipeLeft

  defp analyze(code), do: FixBlockExpressionAsPipeLeft.analyze(code)

  test "flags the unparseable code" do
    code = ~S"""
    defmodule Mod do
      def f(state) do
        if true do
          {:ok, 42}
        end
        |> {state, &1}
      end
    end
    """

    assert [%Issue{rule: :fix_block_expression_as_pipe_left}] = analyze(code)
  end

  test "leaves good code alone" do
    code = ~S"""
    defmodule Mod do
      def f(x), do: x + 1
    end
    """

    assert analyze(code) == []
  end
end
