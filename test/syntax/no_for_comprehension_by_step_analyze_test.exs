defmodule Credence.Syntax.NoForComprehensionByStepAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoForComprehensionByStep

  defp analyze(code), do: NoForComprehensionByStep.analyze(code)

  test "flags the unparseable code" do
    issues =
      analyze("""
      for multiple <- base..(limit - 1) by base do
        multiple
      end
      """)

    assert [%Issue{rule: :no_for_comprehension_by_step}] = issues
  end

  test "leaves good code alone" do
    assert analyze("""
           for x <- 1..10, do: x
           """) == []
  end
end
