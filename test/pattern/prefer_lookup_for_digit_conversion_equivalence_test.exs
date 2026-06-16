defmodule Credence.Pattern.PreferLookupForDigitConversionEquivalenceTest do
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  alias Credence.Pattern.PreferLookupForDigitConversion

  test "fix preserves behaviour for hex digit conversion" do
    assert_equivalent_module(
      """
      defmodule HexExample do
        @spec dec_to_hex(non_neg_integer()) :: String.t()
        def dec_to_hex(0), do: "0"

        def dec_to_hex(number) when is_integer(number) and number > 0 do
          do_dec_to_hex(number, "")
          |> String.upcase()
        end

        defp do_dec_to_hex(0, acc), do: acc

        defp do_dec_to_hex(number, acc) do
          remainder = rem(number, 16)
          new_number = div(number, 16)
          hex_char = hex_digit(remainder)
          do_dec_to_hex(new_number, hex_char <> acc)
        end

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
      """,
      rule: PreferLookupForDigitConversion,
      call: {:dec_to_hex, 1},
      inputs: [1, 10, 15, 255, 4096, 65_535]
    )
  end
end
