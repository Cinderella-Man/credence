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

  test "fixes the ets-match-spec-variable pattern in plain assignment" do
    input = """
    defmodule TestETSMatchSpecVarOutsideComprehension do
      def evict(data_table, order_table) do
        min_ts = :ets.first(order_table)
        [{evicted_key, _}] = :ets.match(data_table, {evicted_key, :"$1"})
        :ets.delete(order_table, min_ts)
        :ets.delete(data_table, evicted_key)
        evicted_key
      end
    end
    """

    expected = """
    defmodule TestETSMatchSpecVarOutsideComprehension do
      def evict(data_table, order_table) do
        min_ts = :ets.first(order_table)
        [{:"$1", _}] = :ets.match(data_table, {:"$1", :"$1"})
        evicted_key = :"$1"
        :ets.delete(order_table, min_ts)
        :ets.delete(data_table, evicted_key)
        evicted_key
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"evicted_key\""), expected)
  end

  test "returns source unchanged when no for-ets-match pattern" do
    source = "x = 1 + 2"
    confirm_fix(fix(source), source)
  end
end
