defmodule Credence.Syntax.NoMixedScriptIdentifierAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoMixedScriptIdentifier

  defp analyze(code), do: NoMixedScriptIdentifier.analyze(code)

  test "flags a defmodule with a mixed Latin+Han identifier" do
    assert [%Issue{rule: :no_mixed_script_identifier, meta: %{line: 5}}] =
             analyze("""
             defmodule Saga do
               def hello, do: :world
             end

             defmodule补偿State do
               def hello, do: :world
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Saga do
             def hello, do: :world
           end
           """) == []
  end
end
