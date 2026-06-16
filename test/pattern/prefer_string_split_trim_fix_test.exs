defmodule Credence.Pattern.PreferStringSplitTrimFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringSplitTrim

  test "rewrites the anti-pattern" do
    input = ~S"""
    sentence
    |> String.split(~r/\s+/)
    |> Enum.filter(&(&1 != ""))
    """

    expected = ~S"""
    sentence
    |> String.split(~r/\s+/, trim: true)
    """

    confirm_fix(fix(PreferStringSplitTrim, input), expected)
  end

  test "rewrites the reversed-operand filter" do
    input = ~S"""
    sentence
    |> String.split(~r/\s+/)
    |> Enum.filter(&("" != &1))
    """

    expected = ~S"""
    sentence
    |> String.split(~r/\s+/, trim: true)
    """

    confirm_fix(fix(PreferStringSplitTrim, input), expected)
  end

  test "leaves good code unchanged" do
    code = ~S"""
    sentence
    |> String.split(",", parts: 3)
    |> Enum.filter(&(&1 != ""))
    """

    confirm_fix(fix(PreferStringSplitTrim, code), code)
  end
end
