defmodule Credence.Pattern.PreferStringFirstLastEquivalenceTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringFirstLast

  test "fix preserves behaviour" do
    assert_equivalent(
      """
      Enum.filter(strings, fn string ->
        case String.split_at(string, 1) do
          {first_char, _rest} ->
            last_char = String.last(string)
            first_char == last_char
        end
      end)
      """,
      rule: PreferStringFirstLast,
      vars: [:strings],
      inputs: [
        ["hello"],
        ["aa", "bb"],
        ["aa", "ab", "hello"],
        ["a", "abba", "xyz"]
      ]
    )
  end
end
