defmodule Credence.Semantic.FixMixedAritiesInAnonFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixMixedAritiesInAnonFn

  @real_diag_msg "cannot mix clauses with different arities in anonymous functions"

  defp fix(source, message, line \\ 1) do
    FixMixedAritiesInAnonFn.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "pads shorter fn clause with _ to match max arity" do
    input = ~S"""
    defmodule MixedArityFn do
      def process(items) do
        Enum.reduce(items, [], fn {name, val}, acc -> [{name, val} | acc] ; _ -> acc end)
      end
    end
    """

    expected = ~S"""
    defmodule MixedArityFn do
      def process(items) do
        Enum.reduce(items, [], fn
          {name, val}, acc -> [{name, val} | acc]
          _, acc -> acc
        end)
      end
    end
    """

    confirm_fix(fix(input, @real_diag_msg), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule MixedArityFn do
      def process(items) do
        Enum.reduce(items, [], fn {name, val}, acc -> [{name, val} | acc] ; _ -> acc end)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_diag_msg))
  end

  test "does not alter fn clauses that already have equal arity" do
    input = ~S"""
    fn x -> x + 1; y -> y * 2 end
    """

    confirm_fix(fix(input, @real_diag_msg), input)
  end
end
