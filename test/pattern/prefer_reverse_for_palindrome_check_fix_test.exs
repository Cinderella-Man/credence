defmodule Credence.Pattern.PreferReverseForPalindromeCheckFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferReverseForPalindromeCheck

  describe "rewrites the anti-pattern" do
    test "replaces index-based recursion with Enum.reverse comparison" do
      input = """
      defmodule Solution do
        def palindrome_check(list) do
          palindrome_helper?(list, 0, length(list) - 1)
        end

        defp palindrome_helper?(_list, left_index, right_index) when left_index >= right_index do
          true
        end

        defp palindrome_helper?(list, left_index, right_index) do
          left_char = Enum.at(list, left_index)
          right_char = Enum.at(list, right_index)

          if left_char == right_char do
            palindrome_helper?(list, left_index + 1, right_index - 1)
          else
            false
          end
        end
      end
      """

      expected = """
      defmodule Solution do
        def palindrome_check(list), do: list == Enum.reverse(list)
      end
      """

      confirm_fix(fix(PreferReverseForPalindromeCheck, input), expected)
    end
  end

  describe "round-trip" do
    test "fixed code produces no issues" do
      code = """
      defmodule Solution do
        def palindrome_check(list) do
          palindrome_helper?(list, 0, length(list) - 1)
        end

        defp palindrome_helper?(_list, left_index, right_index) when left_index >= right_index do
          true
        end

        defp palindrome_helper?(list, left_index, right_index) do
          left_char = Enum.at(list, left_index)
          right_char = Enum.at(list, right_index)

          if left_char == right_char do
            palindrome_helper?(list, left_index + 1, right_index - 1)
          else
            false
          end
        end
      end
      """

      assert clean?(PreferReverseForPalindromeCheck, fix(PreferReverseForPalindromeCheck, code))
    end
  end
end
