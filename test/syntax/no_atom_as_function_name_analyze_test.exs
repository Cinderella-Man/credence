defmodule Credence.Syntax.NoAtomAsFunctionNameAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoAtomAsFunctionName

  defp analyze(code), do: NoAtomAsFunctionName.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_atom_as_function_name, meta: %{line: 1}}] =
             analyze(":ets_table_name(name)")
  end

  test "flags atom-as-function inside a module" do
    code = """
    defmodule M do
      def foo do
        :ets_table_name(__MODULE__)
      end
    end
    """

    assert [%Issue{rule: :no_atom_as_function_name, meta: %{line: 3}}] = analyze(code)
  end

  test "leaves good code alone" do
    assert analyze("ets_table_name(name)") == []
  end

  test "leaves bare atoms without parens alone" do
    assert analyze(":some_atom") == []
  end

  test "leaves atom in keyword list alone" do
    assert analyze("foo(bar: :baz)") == []
  end
end
