defmodule Credence.Pattern.PreferStringCapitalizeCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringCapitalize

  test "flags the anti-pattern" do
    assert flagged?(PreferStringCapitalize, """
           defmodule PatternExample do
             defp capitalize_string(""), do: ""

             defp capitalize_string(string) do
               first_char = String.first(string) |> String.upcase()
               rest = String.slice(string, 1, byte_size(string) - String.length(first_char)) |> String.downcase()
               first_char <> rest
             end
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferStringCapitalize, """
           defmodule PatternExample do
             defp capitalize_string(""), do: ""
             defp capitalize_string(string), do: String.capitalize(string)
           end
           """)
  end

  test "does not flag String.capitalize without manual pattern" do
    assert clean?(PreferStringCapitalize, """
           defmodule Example do
             def capitalize(str), do: String.capitalize(str)
           end
           """)
  end

  test "does not flag unrelated defp" do
    assert clean?(PreferStringCapitalize, """
           defmodule Example do
             defp process(string), do: String.trim(string)
           end
           """)
  end
end
