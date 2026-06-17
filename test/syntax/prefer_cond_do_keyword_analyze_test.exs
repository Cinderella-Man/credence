defmodule Credence.Syntax.PreferCondDoKeywordAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferCondDoKeyword

  defp analyze(code), do: PreferCondDoKeyword.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :prefer_cond_do_keyword}] =
             analyze("""
             defmodule Solution do
               def find_min(list) do
                 cond ->
                   list == [] -> nil
                   true -> Enum.min(list)
                 end
               end
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Solution do
             def find_min(list) do
               cond do
                 list == [] -> nil
                 true -> Enum.min(list)
               end
             end
           end
           """) == []
  end

  test "does not flag a `cond ->` that is only docstring content of an unrelated broken file" do
    assert analyze("""
           defmodule Solution do
             @moduledoc \"\"\"
             Example: cond -> in other languages.
             \"\"\"
             def f(list) do
               Enum.map(list
             end
           end
           """) == []
  end
end
