defmodule Credence.Pattern.PreferPatternMatchingForEmptyStringCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPatternMatchingForEmptyString

  test "flags the anti-pattern" do
    assert flagged?(PreferPatternMatchingForEmptyString, """
           def comma_separated_to_list(input_string) do
             if String.trim(input_string) == "" do
               []
             else
               String.split(input_string, ",")
               |> Enum.map(&String.to_integer/1)
             end
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferPatternMatchingForEmptyString, """
           def comma_separated_to_list(""), do: []
           def comma_separated_to_list(input_string) do
             String.split(input_string, ",")
             |> Enum.map(&String.to_integer/1)
           end
           """)
  end
end
