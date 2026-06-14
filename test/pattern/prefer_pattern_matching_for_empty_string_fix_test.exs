defmodule Credence.Pattern.PreferPatternMatchingForEmptyStringFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPatternMatchingForEmptyString

  test "rewrites the anti-pattern" do
    input = """
    def comma_separated_to_list(input_string) do
      if String.trim(input_string) == "" do
        []
      else
        String.split(input_string, ",")
        |> Enum.map(&String.to_integer/1)
      end
    end
    """

    expected = """
    def comma_separated_to_list(""), do: []
    def comma_separated_to_list(input_string),
      do:
        String.split(input_string, ",")
        |> Enum.map(&String.to_integer/1)
    """

    confirm_fix(fix(PreferPatternMatchingForEmptyString, input), expected)
  end
end
