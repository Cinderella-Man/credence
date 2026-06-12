defmodule Credence.Pattern.PreferLookupForDigitConversionCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.PreferLookupForDigitConversion

  describe "flags" do
    test "16 separate hex digit clauses" do
      assert flagged?(PreferLookupForDigitConversion, """
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
             """)
    end

    test "reports an issue with the correct rule name" do
      issues =
        check(PreferLookupForDigitConversion, """
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
        """)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :prefer_lookup_for_digit_conversion
      assert issue.meta.line != nil
    end
  end

  describe "leaves good code alone" do
    test "single clause function" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               defp hex_digit(remainder) do
                 "0123456789ABCDEF"
                 |> String.at(remainder)
               end
             end
             """)
    end

    test "only numeric digit clauses (0-9, no hex letters)" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               defp digit(0), do: "0"
               defp digit(1), do: "1"
               defp digit(2), do: "2"
               defp digit(3), do: "3"
               defp digit(4), do: "4"
               defp digit(5), do: "5"
               defp digit(6), do: "6"
               defp digit(7), do: "7"
               defp digit(8), do: "8"
               defp digit(9), do: "9"
             end
             """)
    end

    test "non-hex mapping" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               defp letter(0), do: "a"
               defp letter(1), do: "b"
               defp letter(2), do: "c"
             end
             """)
    end

    test "functions with arity > 1" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               defp foo(0, x), do: x
               defp foo(1, x), do: x + 1
             end
             """)
    end

    test "public functions" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               def hex_digit(0), do: "0"
               def hex_digit(1), do: "1"
             end
             """)
    end

    test "empty module" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
             end
             """)
    end
  end
end
