defmodule Credence.Semantic.NoPipeIntoInExpressionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoPipeIntoInExpression

  @msg "cannot pipe to_string(key) into String.downcase() in set, the :in operator can only take two arguments"

  defp fix(source, line \\ 1) do
    NoPipeIntoInExpression.fix(source, %{severity: :error, message: @msg, position: {line, 1}})
  end

  test "wraps piped expression in parens before `in`" do
    input = "to_string(key) |> String.downcase() in set"
    expected = "(to_string(key) |> String.downcase()) in set"
    confirm_fix(fix(input), expected)
  end

  test "does not alter a line without pipe-into-in" do
    line = ~S/String.downcase(key) in set/
    confirm_fix(fix(line), line)
  end

  test "preserves unrelated lines in multi-line source" do
    input = """
    def check(key) do
      String.downcase(key) in set
    end
    """

    expected = """
    def check(key) do
      String.downcase(key) in set
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes multi-line source with pipe-into-in on one line" do
    input = """
    def check(key) do
      to_string(key) |> String.downcase() in set
    end
    """

    expected = """
    def check(key) do
      (to_string(key) |> String.downcase()) in set
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = "to_string(key) |> String.downcase() in set"
    assert valid_syntax?(fix(input))
  end
end
