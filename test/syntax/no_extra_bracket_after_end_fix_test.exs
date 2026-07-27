defmodule Credence.Syntax.NoExtraBracketAfterEndFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoExtraBracketAfterEnd

  defp analyze(code), do: NoExtraBracketAfterEnd.analyze(code)
  defp fix(code), do: NoExtraBracketAfterEnd.fix(code)

  test "fixes the syntax error" do
    input = """
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

    expected = """
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

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
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

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
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

    assert valid_syntax?(fix(input))
  end
end
