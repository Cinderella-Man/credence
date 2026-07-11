defmodule Credence.Syntax.NoAtomAsFunctionNameFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoAtomAsFunctionName

  defp analyze(code), do: NoAtomAsFunctionName.analyze(code)
  defp fix(code), do: NoAtomAsFunctionName.fix(code)

  test "fixes the syntax error" do
    input = ":ets_table_name(name)"
    expected = "ets_table_name(name)"

    confirm_fix(fix(input), expected)
  end

  test "fixes atom-as-function in a module context" do
    input = """
    defmodule M do
      def foo do
        :ets_table_name(__MODULE__)
      end

      defp ets_table_name(name) do
        String.to_atom("metrics_" <> to_string(name))
      end
    end
    """

    expected = """
    defmodule M do
      def foo do
        ets_table_name(__MODULE__)
      end

      defp ets_table_name(name) do
        String.to_atom("metrics_" <> to_string(name))
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix(":ets_table_name(name)")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(":ets_table_name(name)"))
  end

  test "leaves already-clean source unchanged" do
    input = "ets_table_name(name)"
    confirm_fix(fix(input), input)
  end

  test "fixes multiple occurrences" do
    input = ":foo(x) + :bar(y)"
    expected = "foo(x) + bar(y)"

    confirm_fix(fix(input), expected)
  end
end
