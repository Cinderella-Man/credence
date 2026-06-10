defmodule Credence.Pattern.PreferStringFirstLastCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringFirstLast

  test "flags the anti-pattern" do
    assert flagged?(PreferStringFirstLast, """
           Enum.filter(strings, fn string ->
             case String.split_at(string, 1) do
               {first_char, _rest} ->
                 last_char = String.last(string)
                 first_char == last_char
             end
           end)
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferStringFirstLast, """
           Enum.filter(strings, fn string ->
             String.first(string) == String.last(string)
           end)
           """)
  end
end
