defmodule Credence.Pattern.PreferIntegerDigitsForFirstDigitFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferIntegerDigitsForFirstDigit

  test "rewrites the anti-pattern" do
    input = """
    number
    |> abs()
    |> to_string()
    |> String.first()
    |> String.to_integer()
    """

    expected = """
    number
    |> abs()
    |> Integer.digits()
    |> hd()
    """

    assert fix(PreferIntegerDigitsForFirstDigit, input) == expected
  end

  test "rewrites the anti-pattern in a function" do
    input = """
    defmodule Example do
      def first_digit(number) do
        number
        |> abs()
        |> to_string()
        |> String.first()
        |> String.to_integer()
      end
    end
    """

    expected = """
    defmodule Example do
      def first_digit(number) do
        number
        |> abs()
        |> Integer.digits()
        |> hd()
      end
    end
    """

    assert fix(PreferIntegerDigitsForFirstDigit, input) == expected
  end

  test "does not modify code that is already correct" do
    code = """
    number
    |> abs()
    |> Integer.digits()
    |> hd()
    """

    assert fix(PreferIntegerDigitsForFirstDigit, code) == code
  end
end
