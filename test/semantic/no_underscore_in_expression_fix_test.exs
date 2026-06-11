defmodule Credence.Semantic.NoUnderscoreInExpressionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.NoUnderscoreInExpression

  defp fix(source, message, line \\ 1) do
    NoUnderscoreInExpression.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    defmodule Example do
      def build_map(n) do
        for _ <- 0..(n - 1), into: %{} do
          {_, :infinity}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def build_map(n) do
        for idx <- 0..(n - 1), into: %{} do
          {idx, :infinity}
        end
      end
    end
    """

    message =
      "redefining module Solution (current version loaded from _build/test/lib/workspace/ebin/Elixir.Solution.beam)"

    assert fix(input, message) == expected
  end

  test "fixed output is well-formed (parses)" do
    message =
      "redefining module Solution (current version loaded from _build/test/lib/workspace/ebin/Elixir.Solution.beam)"

    assert valid_syntax?(
             fix(
               """
               defmodule Example do
                 def build_map(n) do
                   for _ <- 0..(n - 1), into: %{} do
                     {_, :infinity}
                   end
                 end
               end
               """,
               message
             )
           )
  end

  test "returns source unchanged when no underscore in expression" do
    input = """
    defmodule Example do
      def build_map(n) do
        for i <- 0..(n - 1), into: %{} do
          {i, :infinity}
        end
      end
    end
    """

    message =
      "redefining module Solution (current version loaded from _build/test/lib/workspace/ebin/Elixir.Solution.beam)"

    assert fix(input, message) == input
  end
end
