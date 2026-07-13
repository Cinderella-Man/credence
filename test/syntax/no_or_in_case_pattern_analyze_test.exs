defmodule Credence.Syntax.NoOrInCasePatternAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoOrInCasePattern

  defp analyze(code), do: NoOrInCasePattern.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_or_in_case_pattern}] =
             analyze("""
             defmodule Example do
               def match(val) do
                 case val do
                   nil or "" -> :empty
                   _ -> :ok
                 end
               end
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Example do
             def match(val) do
               case val do
                 nil -> :empty
                 "" -> :empty
                 _ -> :ok
               end
             end
           end
           """) == []
  end

  test "flags nested or" do
    issues =
      analyze("""
      defmodule Example do
        def match(val) do
          case val do
            nil or "" or false -> :empty
            _ -> :ok
          end
        end
      end
      """)

    assert length(issues) >= 1
    assert Enum.all?(issues, &(&1.rule == :no_or_in_case_pattern))
  end
end
