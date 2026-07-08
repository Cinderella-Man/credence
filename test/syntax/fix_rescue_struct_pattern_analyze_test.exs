defmodule Credence.Syntax.FixRescueStructPatternAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixRescueStructPattern

  defp analyze(code), do: FixRescueStructPattern.analyze(code)

  test "flags the unparseable code" do
    code = """
    try do
      loader_fn.()
    rescue
      %FunctionClauseError -> {:error, :function_clause}
      %ArgumentError -> {:error, :argument}
    end
    """

    assert [%Issue{rule: :fix_rescue_struct_pattern}, %Issue{rule: :fix_rescue_struct_pattern}] =
             analyze(code)
  end

  test "leaves good code alone" do
    code = """
    try do
      loader_fn.()
    rescue
      e in FunctionClauseError -> {:error, :function_clause}
      e in ArgumentError -> {:error, :argument}
    end
    """

    assert analyze(code) == []
  end
end
