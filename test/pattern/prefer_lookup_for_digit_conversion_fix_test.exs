defmodule Credence.Pattern.PreferLookupForDigitConversionFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferLookupForDigitConversion

  test "rewrites 16 hex digit clauses to string lookup" do
    input = """
    defmodule Solution do
      defp hex_digit(0), do: "0"
      defp hex_digit(1), do: "1"
      defp hex_digit(2), do: "2"
      defp hex_digit(3), do: "3"
      defp hex_digit(4), do: "4"
      defp hex_digit(5), do: "5"
      defp hex_digit(6), do: "6"
      defp hex_digit(7), do: "7"
      defp hex_digit(8), do: "8"
      defp hex_digit(9), do: "9"
      defp hex_digit(10), do: "A"
      defp hex_digit(11), do: "B"
      defp hex_digit(12), do: "C"
      defp hex_digit(13), do: "D"
      defp hex_digit(14), do: "E"
      defp hex_digit(15), do: "F"
    end
    """

    expected = """
    defmodule Solution do
      defp hex_digit(remainder) when remainder in 0..15 do
        "0123456789ABCDEF" |> String.at(remainder)
      end
    end
    """

    confirm_fix(fix(PreferLookupForDigitConversion, input), expected)
  end

  test "leaves code without hex digit anti-pattern unchanged" do
    code = """
    defmodule Good do
      defp hex_digit(remainder) do
        "0123456789ABCDEF"
        |> String.at(remainder)
      end
    end
    """

    confirm_fix(fix(PreferLookupForDigitConversion, code), code)
  end

  test "leaves empty module unchanged" do
    code = """
    defmodule Good do
    end
    """

    confirm_fix(fix(PreferLookupForDigitConversion, code), code)
  end
end
