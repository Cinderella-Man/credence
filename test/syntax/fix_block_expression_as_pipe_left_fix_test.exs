defmodule Credence.Syntax.FixBlockExpressionAsPipeLeftFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixBlockExpressionAsPipeLeft

  defp analyze(code), do: FixBlockExpressionAsPipeLeft.analyze(code)
  defp fix(code), do: FixBlockExpressionAsPipeLeft.fix(code)

  test "fixes the syntax error" do
    input = ~S"""
    defmodule Mod do
      def f(state) do
        if true do
          {:ok, 42}
        end
        |> {state, &1}
      end
    end
    """

    expected = ~S"""
    defmodule Mod do
      def f(state) do
        if_result =
          if true do
            {:ok, 42}
          end

        {state, if_result}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = ~S"""
    defmodule Mod do
      def f(state) do
        if true do
          {:ok, 42}
        end
        |> {state, &1}
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule Mod do
      def f(state) do
        if true do
          {:ok, 42}
        end
        |> {state, &1}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
