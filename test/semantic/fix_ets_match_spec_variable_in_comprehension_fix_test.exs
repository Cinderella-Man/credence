defmodule Credence.Semantic.FixEtsMatchSpecVariableInComprehensionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixEtsMatchSpecVariableInComprehension

  @message "undefined variable \"name\""

  defp fix(source, message \\ @message, line \\ 1) do
    FixEtsMatchSpecVariableInComprehension.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the for-ets-match-spec-variable pattern" do
    input = """
    defmodule MatchSpecVarBug do
      def all(table) do
        for {name, _type, value} <- :ets.match(table, {name, :_, :"$1"}) do
          {name, value}
        end
        |> Map.new()
      end
    end
    """

    expected = """
    defmodule MatchSpecVarBug do
      def all(table) do
        :ets.match(table, {:"$1", :_, :"$2"})
        |> Enum.map(fn [name, value] -> {name, value} end)
        |> Map.new()
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("foo(bar)"))
  end

  test "returns source unchanged when no for-ets-match pattern" do
    source = "x = 1 + 2"
    confirm_fix(fix(source), source)
  end
end
