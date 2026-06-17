defmodule Credence.Pattern.PreferStringSplitTrimCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringSplitTrim

  test "flags the anti-pattern" do
    assert flagged?(PreferStringSplitTrim, ~S"""
           sentence
           |> String.split(~r/\s+/)
           |> Enum.filter(&(&1 != ""))
           """)
  end

  test "flags the reversed-operand filter" do
    assert flagged?(PreferStringSplitTrim, ~S"""
           sentence
           |> String.split(~r/\s+/)
           |> Enum.filter(&("" != &1))
           """)
  end

  test "leaves already-trimmed split alone" do
    assert clean?(PreferStringSplitTrim, ~S"""
           sentence
           |> String.split(~r/\s+/, trim: true)
           """)
  end

  # --- boundary: the fix only adds `trim: true`, so it must NOT fire when the
  # split already carries options (the merge would be wrong) ---
  test "does not fire when String.split already has options" do
    assert clean?(PreferStringSplitTrim, ~S"""
           sentence
           |> String.split(",", parts: 3)
           |> Enum.filter(&(&1 != ""))
           """)
  end

  # --- boundary: the filter must remove empty strings specifically; any other
  # predicate is not equivalent to `trim: true` ---
  test "does not fire when the filter removes something other than empty string" do
    assert clean?(PreferStringSplitTrim, ~S"""
           sentence
           |> String.split(",")
           |> Enum.filter(&(&1 != nil))
           """)
  end

  # --- boundary: the split must be the step directly before the filter ---
  test "does not fire when split is not directly before the filter" do
    assert clean?(PreferStringSplitTrim, ~S"""
           sentence
           |> String.split(",")
           |> Enum.map(&String.trim/1)
           |> Enum.filter(&(&1 != ""))
           """)
  end
end
