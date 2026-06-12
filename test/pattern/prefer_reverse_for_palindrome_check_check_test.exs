defmodule Credence.Pattern.PreferReverseForPalindromeCheckCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferReverseForPalindromeCheck

  describe "flags the anti-pattern" do
    test "detects index-based recursive palindrome check" do
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

      issues = check(PreferReverseForPalindromeCheck, code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_reverse_for_palindrome_check
    end
  end

  describe "leaves good code alone" do
    test "does not flag idiomatic list == Enum.reverse(list)" do
      code = """
      defmodule Solution do
        def palindrome_check(list) do
          list == Enum.reverse(list)
        end
      end
      """

      assert clean?(PreferReverseForPalindromeCheck, code)
    end

    test "does not flag unrelated functions" do
      code = """
      defmodule Unrelated do
        def foo(x), do: x + 1
        def bar(y), do: y * 2
      end
      """

      assert clean?(PreferReverseForPalindromeCheck, code)
    end

    test "does not flag partial matches missing the helper" do
      code = """
      defmodule Partial do
        def palindrome_check(list) do
          Enum.reverse(list) == list
        end
      end
      """

      assert clean?(PreferReverseForPalindromeCheck, code)
    end
  end
end
