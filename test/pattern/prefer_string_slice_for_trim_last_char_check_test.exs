defmodule Credence.Pattern.PreferStringSliceForTrimLastCharCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringSliceForTrimLastChar

  test "flags the anti-pattern" do
    assert flagged?(PreferStringSliceForTrimLastChar, """
           defmodule Example do
             def trim_last_char(str) when is_binary(str) do
               case String.graphemes(str) do
                 [] -> ""
                 [_last] -> ""
                 [_head | _tail] -> String.slice(str, 0, String.length(str) - 1)
               end
             end
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferStringSliceForTrimLastChar, """
           defmodule Example do
             def trim_last_char(str) when is_binary(str) do
               String.slice(str, 0..-2//1)
             end
           end
           """)
  end

  test "does not flag a case with different patterns" do
    assert clean?(PreferStringSliceForTrimLastChar, """
           case String.graphemes(str) do
             [] -> :empty
             _ -> :non_empty
           end
           """)
  end

  test "does not flag a case with different subject" do
    assert clean?(PreferStringSliceForTrimLastChar, """
           case some_function(str) do
             [] -> ""
             [_last] -> ""
             [_head | _tail] -> String.slice(str, 0, String.length(str) - 1)
           end
           """)
  end

  test "does not flag a case with different body in third clause" do
    assert clean?(PreferStringSliceForTrimLastChar, """
           case String.graphemes(str) do
             [] -> ""
             [_last] -> ""
             [_head | _tail] -> String.slice(str, 0, String.length(str) - 2)
           end
           """)
  end
end
