defmodule Credence.Syntax.NoExtraBracketAfterEndAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoExtraBracketAfterEnd

  defp analyze(code), do: NoExtraBracketAfterEnd.analyze(code)

  test "flags the unparseable code" do
    code = ~S"""
    defmodule M do
      def f do
        cond do
          true ->
            case :ok do
              :ok -> 1
            end]
        end
      end
    end
    """

    assert [%Issue{rule: :no_extra_bracket_after_end}] = analyze(code)
  end

  test "leaves good code alone" do
    code = ~S"""
    defmodule M do
      def f do
        cond do
          true ->
            case :ok do
              :ok -> 1
            end
        end
      end
    end
    """

    assert analyze(code) == []
  end
end
