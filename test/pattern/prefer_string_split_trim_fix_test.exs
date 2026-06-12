defmodule Credence.Pattern.PreferStringSplitTrimFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringSplitTrim

  test "rewrites the anti-pattern" do
    input = """
    sentence
    |> String.split(~r/\s+/)
    |> Enum.filter(&(&1 != ""))
    """

    expected = """
    sentence
    |> String.split(~r/\s+/, trim: true)
    """

    assert fix(PreferStringSplitTrim, input) == expected
  end
end
