defmodule Credence.Pattern.PreferStringFirstLastFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringFirstLast

  test "rewrites the anti-pattern" do
    input = """
    Enum.filter(strings, fn string ->
      case String.split_at(string, 1) do
        {first_char, _rest} ->
          last_char = String.last(string)
          first_char == last_char
      end
    end)
    """

    expected = """
    Enum.filter(strings, fn string ->
      String.first(string) == String.last(string)
    end)
    """

    assert fix(PreferStringFirstLast, input) == expected
  end
end
