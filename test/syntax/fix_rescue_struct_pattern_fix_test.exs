defmodule Credence.Syntax.FixRescueStructPatternFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixRescueStructPattern

  defp analyze(code), do: FixRescueStructPattern.analyze(code)
  defp fix(code), do: FixRescueStructPattern.fix(code)

  test "fixes the syntax error" do
    input = """
    try do
      loader_fn.()
    rescue
      %FunctionClauseError -> {:error, :function_clause}
      %ArgumentError -> {:error, :argument}
    end
    """

    expected = """
    try do
      loader_fn.()
    rescue
      e in FunctionClauseError -> {:error, :function_clause}
      e in ArgumentError -> {:error, :argument}
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    try do
      loader_fn.()
    rescue
      %FunctionClauseError -> {:error, :function_clause}
      %ArgumentError -> {:error, :argument}
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    try do
      loader_fn.()
    rescue
      %FunctionClauseError -> {:error, :function_clause}
      %ArgumentError -> {:error, :argument}
    end
    """

    assert valid_syntax?(fix(input))
  end
end
