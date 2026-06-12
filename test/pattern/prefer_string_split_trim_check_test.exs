defmodule Credence.Pattern.PreferStringSplitTrimCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringSplitTrim

  test "flags the anti-pattern" do
    assert flagged?(PreferStringSplitTrim, """
           sentence
           |> String.split(~r/\s+/)
           |> Enum.filter(&(&1 != ""))
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferStringSplitTrim, """
           sentence
           |> String.split(~r/\s+/, trim: true)
           """)
  end
end
