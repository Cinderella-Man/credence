defmodule Credence.Syntax.NoDefpQualifiedNameAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoDefpQualifiedName

  defp analyze(code), do: NoDefpQualifiedName.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_defp_qualified_name}] =
             analyze("""
             defmodule Broken do
               defp Macro.expand({mod, fun, args}, _env) do
                 fn -> apply(mod, fun, args) end
               end
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Good do
             defp expand({mod, fun, args}, _env) do
               fn -> apply(mod, fun, args) end
             end
           end
           """) == []
  end
end
