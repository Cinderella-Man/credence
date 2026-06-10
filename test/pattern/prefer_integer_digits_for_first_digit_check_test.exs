defmodule Credence.Pattern.PreferIntegerDigitsForFirstDigitCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferIntegerDigitsForFirstDigit

  test "flags the anti-pattern" do
    assert flagged?(PreferIntegerDigitsForFirstDigit, """
           number
           |> abs()
           |> to_string()
           |> String.first()
           |> String.to_integer()
           """)
  end

  test "flags the anti-pattern in a function" do
    assert flagged?(PreferIntegerDigitsForFirstDigit, """
           defmodule Example do
             def first_digit(number) do
               number
               |> abs()
               |> to_string()
               |> String.first()
               |> String.to_integer()
             end
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferIntegerDigitsForFirstDigit, """
           number
           |> abs()
           |> Integer.digits()
           |> hd()
           """)
  end

  test "leaves unrelated code alone" do
    assert clean?(PreferIntegerDigitsForFirstDigit, """
           defmodule Unrelated do
             def hello, do: :world
           end
           """)
  end
end
